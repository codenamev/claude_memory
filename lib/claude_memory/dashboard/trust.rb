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
      STALE_DAYS = 30
      VALUE_EVENT_TYPES = %w[hook_context recall store_extraction].freeze

      def initialize(manager)
        @manager = manager
      end

      def snapshot
        {
          weekly_moments: weekly_moments,
          fingerprint: fingerprint,
          needs_review: needs_review
        }
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
        counts = {project: 0, global: 0}
        %w[project global].each do |scope|
          store = @manager.store_if_exists(scope)
          next unless store
          counts[scope.to_sym] = store.conflicts.where(status: "open").count
        end
        counts.merge(total: counts.values.sum)
      rescue Sequel::DatabaseError
        {project: 0, global: 0, total: 0}
      end

      # "Stale" = active facts not referenced by a recall in the last STALE_DAYS.
      # Uses scoped (scope, id) pairs so a project recall of fact #5 doesn't
      # incidentally mark global fact #5 as "seen recently."
      def count_stale_facts
        store = @manager.default_store(prefer: :project)
        return 0 unless store

        cutoff = (Time.now.utc - STALE_DAYS * 86_400).iso8601
        seen_pairs = Set.new
        store.activity_events
          .where(event_type: "recall", status: "success")
          .where { occurred_at >= cutoff }
          .select(:detail_json)
          .all
          .each do |row|
            details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
            scoped = ScopedFactResolver.scoped_ids_from_details(details)
            ScopedFactResolver.flat_pairs(scoped).each { |pair| seen_pairs << pair }
          end

        # No recalls yet → don't nag; the system hasn't had a chance to use
        # anything. (Differs from "recalls happened but facts A, B, C weren't
        # in any of them.")
        return 0 if seen_pairs.empty?

        total_active = 0
        %w[project global].each do |scope|
          s = @manager.store_if_exists(scope)
          next unless s
          total_active += s.facts.where(status: "active").count
        end
        [total_active - seen_pairs.size, 0].max
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("Trust#count_stale_facts failed: #{e.message}")
        0
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
