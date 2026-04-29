# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Sidebar data for the feed-first dashboard. Three things:
    #
    # 1. Moments this week + week-over-week delta — the headline value number.
    #    A moment is any meaningful activity event (recall hit, extraction,
    #    context injection, conflict detected). Ingest-only events don't count
    #    because they're not directly user-visible value.
    #
    # 2. "What memory knows about you" — up to 5 global facts rendered as
    #    plain English. This is the trust panel's most compelling surface:
    #    users can sanity-check what's being injected into their sessions.
    #
    # 3. Needs review — open conflicts plus facts that have gone stale
    #    (active but never recalled in the last N days). A single actionable
    #    count; the feed surfaces the individual items.
    class Trust
      WEEK_SECONDS = 7 * 86_400
      UTILIZATION_DAYS = 30
      VALUE_EVENT_TYPES = %w[hook_context recall store_extraction].freeze

      def initialize(manager)
        @manager = manager
      end

      def snapshot
        {
          weekly_moments: weekly_moments,
          fingerprint: fingerprint,
          needs_review: needs_review,
          utilization: utilization,
          feedback: feedback_summary,
          token_budget: token_budget
        }
      end

      # What does memory cost? Aggregates `context_tokens` from successful
      # `hook_context` activity events over the last UTILIZATION_DAYS so a
      # skeptical user can see the per-session token cost in p50/p95.
      #
      # Shape: {p50:, p95:, avg:, sample_size:, window_days:}
      # All ints. Returns zeros when there are no events in the window.
      def token_budget
        store = @manager.default_store(prefer: :project)
        return token_budget_zero unless store

        cutoff = (Time.now.utc - UTILIZATION_DAYS * 86_400).iso8601
        rows = store.activity_events
          .where(event_type: "hook_context", status: "success")
          .where { occurred_at >= cutoff }
          .select(:detail_json)
          .all

        tokens = rows.filter_map do |row|
          details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
          value = details["context_tokens"]
          value if value.is_a?(Integer) && value > 0
        end

        return token_budget_zero if tokens.empty?

        sorted = tokens.sort
        {
          p50: percentile(sorted, 0.50),
          p95: percentile(sorted, 0.95),
          avg: (sorted.sum.to_f / sorted.size).round,
          sample_size: sorted.size,
          window_days: UTILIZATION_DAYS
        }
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("Trust#token_budget failed: #{e.message}")
        token_budget_zero
      end
      public :token_budget

      def token_budget_zero
        {p50: 0, p95: 0, avg: 0, sample_size: 0, window_days: UTILIZATION_DAYS}
      end

      def percentile(sorted, pct)
        return 0 if sorted.empty?
        idx = (sorted.size * pct).ceil - 1
        idx = 0 if idx < 0
        idx = sorted.size - 1 if idx >= sorted.size
        sorted[idx]
      end

      private

      def weekly_moments
        store = @manager.default_store(prefer: :project)
        return {this_week: 0, last_week: 0, delta: 0, by_kind: {}} unless store

        now = Time.now.utc
        this_week_since = (now - WEEK_SECONDS).iso8601
        last_week_since = (now - 2 * WEEK_SECONDS).iso8601

        this_rows = valuable_events(store, this_week_since)
        last_rows = valuable_events(store, last_week_since, before: this_week_since)

        by_kind = this_rows.group_by { |r| r[:event_type] }.transform_values(&:size)

        {
          this_week: this_rows.size,
          last_week: last_rows.size,
          delta: this_rows.size - last_rows.size,
          by_kind: by_kind
        }
      rescue Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("Trust#weekly_moments failed: #{e.message}")
        {this_week: 0, last_week: 0, delta: 0, by_kind: {}}
      end

      def valuable_events(store, since, before: nil)
        dataset = store.activity_events
          .where(event_type: VALUE_EVENT_TYPES)
          .where(status: "success")
          .where { occurred_at >= since }
        dataset = dataset.where { occurred_at < before } if before
        dataset.all
      end

      # Up to 5 global facts rendered as plain-English sentences so a skeptical
      # user can verify at-a-glance what's being injected into their Claude
      # sessions. Prefers high-signal predicates (convention, decision,
      # uses_framework, uses_database) and falls back to most-recent active.
      def fingerprint
        store = @manager.store_if_exists("global")
        return [] unless store

        preferred_predicates = %w[convention decision uses_framework uses_database uses_language]
        rows = store.facts
          .where(status: "active", scope: "global")
          .where(predicate: preferred_predicates)
          .order(Sequel.desc(:confidence), Sequel.desc(:created_at))
          .limit(5)
          .all

        if rows.size < 5
          extra = store.facts
            .where(status: "active", scope: "global")
            .exclude(id: rows.map { |r| r[:id] })
            .order(Sequel.desc(:created_at))
            .limit(5 - rows.size)
            .all
          rows += extra
        end

        presenter = FactPresenter.new(store)
        presenter.list_summary(rows).map { |f| render_sentence(f) }
      rescue Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("Trust#fingerprint failed: #{e.message}")
        []
      end

      def render_sentence(fact)
        predicate = fact[:predicate]
        object = fact[:object]
        subject = fact[:subject]

        sentence = case predicate
        when "convention"
          object
        when "decision"
          object
        when "uses_framework", "uses_language"
          "Uses #{object}"
        when "uses_database"
          "Uses #{object} for storage"
        when "deployment_platform"
          "Deploys to #{object}"
        when "auth_method"
          "Auth via #{object}"
        else
          "#{subject} #{predicate.tr("_", " ")} #{object}"
        end

        {
          id: fact[:id],
          docid: fact[:docid],
          sentence: sentence.to_s.strip,
          predicate: predicate,
          confidence: fact[:confidence]
        }
      end

      def needs_review
        {
          open_conflicts: count_open_conflicts,
          stale_facts: count_stale_facts,
          empty_recalls: count_empty_recalls
        }
      end

      def count_open_conflicts
        Conflicts.new(@manager).distinct_open_counts
      rescue Sequel::DatabaseError
        {project: 0, global: 0, total: 0}
      end

      # User-supplied thumbs on feed moments. The ratio answers "when Claude
      # surfaces something from memory, is the user signaling it was helpful?"
      # Only moments recorded in the last UTILIZATION_DAYS count toward the
      # ratio so old clicks don't distort an active week's signal.
      #
      # Shape: {up: Int, down: Int, net: Int, ratio_pct: Int, window_days: Int}
      # ratio_pct = up / (up + down) × 100, or nil when there's no feedback.
      def feedback_summary
        store = @manager.default_store(prefer: :project)
        return feedback_zero unless store

        cutoff = (Time.now.utc - UTILIZATION_DAYS * 86_400).iso8601
        rows = store.moment_feedback.where { recorded_at >= cutoff }.all
        up = rows.count { |r| r[:verdict] == "up" }
        down = rows.count { |r| r[:verdict] == "down" }
        total = up + down
        ratio_pct = total.zero? ? nil : ((up.to_f / total) * 100).round

        {up: up, down: down, net: up - down, ratio_pct: ratio_pct, window_days: UTILIZATION_DAYS}
      rescue Sequel::DatabaseError
        feedback_zero
      end

      def feedback_zero
        {up: 0, down: 0, net: 0, ratio_pct: nil, window_days: UTILIZATION_DAYS}
      end

      # "Stale" = active facts whose last_recalled_at is older than the
      # configured threshold (or never set, with a grace window so freshly
      # extracted facts don't show up as stale on day one).
      #
      # Backed by Recall::StaleDetector, which reads the column populated by
      # Sweep::RecallTimestampRefresher. Replaces the older "active facts
      # minus seen-in-recalls" approximation, which couldn't distinguish a
      # never-touched 6-month-old fact from a freshly stored one.
      def count_stale_facts
        threshold = Configuration.new.stale_days
        Recall::StaleDetector.stale_count(@manager, threshold_days: threshold)
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("Trust#count_stale_facts failed: #{e.message}")
        0
      end

      # The ROI signal: of the facts Claude has extracted into memory over the
      # last UTILIZATION_DAYS, how many has Claude actually *used* (appeared
      # in any recall or context injection's top_fact_ids)? Low ratios are
      # themselves a signal — it means memory is accumulating knowledge but
      # Claude isn't reaching for it. Anomalies worth surfacing honestly.
      #
      # Shape: {extracted: Int, used: Int, ratio_pct: Int, window_days: Int}
      # Both counts are scope-union (project + global) so the headline number
      # reflects everything memory did, not just one store.
      def utilization
        cutoff = (Time.now.utc - UTILIZATION_DAYS * 86_400).iso8601
        extracted_pairs = extracted_fact_pairs(cutoff)
        used_pairs = used_fact_pairs(cutoff)

        extracted = extracted_pairs.size
        # "Used" counted against the extracted set — a fact used but not
        # extracted in this window (taught earlier, used now) is still
        # re-use worth recognizing; count it too.
        used_from_extracted = (used_pairs & extracted_pairs).size
        used_total = used_pairs.size

        ratio_pct = extracted.zero? ? 0 : ((used_from_extracted.to_f / extracted) * 100).round

        {
          extracted: extracted,
          used: used_total,
          used_from_extracted: used_from_extracted,
          ratio_pct: ratio_pct,
          window_days: UTILIZATION_DAYS
        }
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("Trust#utilization failed: #{e.message}")
        {extracted: 0, used: 0, used_from_extracted: 0, ratio_pct: 0, window_days: UTILIZATION_DAYS}
      end
      public :utilization

      # Facts that were extracted (distilled + stored) within the window.
      # Returns (scope, id) pairs across both stores.
      def extracted_fact_pairs(cutoff)
        pairs = Set.new
        %w[project global].each do |scope|
          store = @manager.store_if_exists(scope)
          next unless store
          store.facts
            .where(status: "active")
            .where { created_at >= cutoff }
            .select(:id)
            .all
            .each { |r| pairs << [scope, r[:id]] }
        end
        pairs
      end

      # Facts that appeared as top_fact_ids in any recall or context injection
      # within the window. Returns (scope, id) pairs.
      def used_fact_pairs(cutoff)
        store = @manager.default_store(prefer: :project)
        return Set.new unless store
        pairs = Set.new
        store.activity_events
          .where(event_type: %w[recall hook_context], status: "success")
          .where { occurred_at >= cutoff }
          .select(:detail_json)
          .all
          .each do |row|
            details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
            scoped = ScopedFactResolver.scoped_ids_from_details(details)
            ScopedFactResolver.flat_pairs(scoped).each { |pair| pairs << pair }
          end
        pairs
      end

      def count_empty_recalls
        store = @manager.default_store(prefer: :project)
        return 0 unless store

        cutoff = (Time.now.utc - WEEK_SECONDS).iso8601
        store.activity_events
          .where(event_type: "recall")
          .where(status: "success")
          .where { occurred_at >= cutoff }
          .all
          .count do |row|
            details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
            (details["result_count"] || 0).zero?
          end
      rescue Sequel::DatabaseError, JSON::ParserError
        0
      end
    end
  end
end
