# frozen_string_literal: true

module ClaudeMemory
  module Hook
    class Handler
      class PayloadError < ClaudeMemory::Error; end

      DEFAULT_SWEEP_BUDGET = 5

      def initialize(store, env: ENV, manager: nil)
        @store = store
        @manager = manager
        @config = Configuration.new(env)
        @env = env
      end

      def ingest(payload)
        session_id = payload["session_id"] || @config.session_id
        transcript_path = payload["transcript_path"] || @config.transcript_path
        project_path = payload["project_path"] || @config.project_dir

        raise PayloadError, "Missing required field: session_id" if session_id.nil? || session_id.empty?
        raise PayloadError, "Missing required field: transcript_path" if transcript_path.nil? || transcript_path.empty?

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        ingester = Ingest::Ingester.new(@store, env: @env)
        result = ingester.ingest(
          source: "claude_code",
          session_id: session_id,
          transcript_path: transcript_path,
          project_path: project_path
        )

        if result[:status] == :ingested && result[:content_id]
          DistillationRunner.new(@store).distill_item(
            result[:content_id], project_path: project_path
          )
        end

        log_activity("hook_ingest",
          status: (result[:status] == :ingested) ? "success" : "skipped",
          session_id: session_id, t0: t0,
          details: {bytes_read: result[:bytes_read], content_id: result[:content_id],
                    reason: result[:reason]}.compact)

        result
      rescue Ingest::TranscriptReader::FileNotFoundError => e
        log_activity("hook_ingest", status: "skipped", session_id: session_id, t0: t0,
          details: {reason: "transcript_not_found"})
        {status: :skipped, reason: "transcript_not_found", message: e.message}
      end

      def sweep(payload)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        budget = payload.fetch("budget", DEFAULT_SWEEP_BUDGET).to_i
        sweeper = Sweep::Sweeper.new(@store)
        stats = sweeper.run!(budget_seconds: budget)
        stats[:recall_timestamps_refreshed] = refresh_recall_timestamps

        log_activity("hook_sweep", status: "success", t0: t0,
          details: {elapsed_seconds: stats[:elapsed_seconds],
                    budget_honored: stats[:budget_honored]})

        {stats: stats}
      end

      # Sweep-derived staleness data. Skips silently if the sweep was given a
      # store-only handler (no manager); the cross-DB refresher requires the
      # manager because project events can touch global facts and vice versa.
      def refresh_recall_timestamps
        return {project: 0, global: 0} unless @manager
        Sweep::RecallTimestampRefresher.new(@manager).refresh!
      rescue Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("recall timestamp refresh failed: #{e.message}")
        {project: 0, global: 0, error: e.message}
      end

      def publish(payload)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        mode = payload.fetch("mode", "shared").to_sym
        since = payload["since"]
        rules_dir = payload["rules_dir"]

        publisher = Publish.new(@store)
        result = publisher.publish!(mode: mode, since: since, rules_dir: rules_dir)

        log_activity("hook_publish", status: "success", t0: t0,
          details: {mode: mode.to_s, publish_status: result[:status].to_s})

        result
      end

      # First-week ROI nudge. Computes per-session metrics (facts
      # contributed via Stop-hook ingest, percentage of those Claude
      # actually used in recall/context-injection) and decides whether
      # to print to the user. Quiets after MAX_NUDGES successful runs
      # or when CLAUDE_MEMORY_NO_NUDGE=1.
      #
      # The "first ~10 sessions" gate is enforced by counting prior
      # `roi_nudge` activity events with status=success across both
      # stores. Once the user has seen the nudge enough times, memory
      # gets out of the way; trust is established or it isn't.
      MAX_NUDGES = 10
      ENV_NUDGE_OPT_OUT = "CLAUDE_MEMORY_NO_NUDGE"

      def nudge(payload)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        session_id = payload["session_id"] || @config.session_id

        # Cleanly silent on opt-out — no activity event, no record of
        # having tried. Users who set the env var don't want a paper
        # trail of suppressed nudges.
        return {status: :silent, reason: "opt_out"} if @env[ENV_NUDGE_OPT_OUT] == "1"
        return {status: :silent, reason: "no_session_id"} if session_id.nil? || session_id.empty?

        prior = prior_nudge_count
        if prior >= MAX_NUDGES
          return {status: :silent, reason: "first_week_complete", prior_count: prior}
        end

        contributed_ids = session_contributed_facts(session_id)
        n = contributed_ids.size

        if n.zero?
          # Don't burn one of the user's 10 nudge slots on an empty
          # session. Memory contributed nothing → no trust signal to
          # surface; come back next session with real data.
          return {status: :silent, reason: "no_contributions", prior_count: prior}
        end

        used = session_used_facts(session_id, contributed_ids)
        pct = (used * 100.0 / n).round
        message = "memory contributed #{n} fact#{"s" unless n == 1} this session, %used = #{pct}%"

        log_activity("roi_nudge", status: "success", session_id: session_id, t0: t0,
          details: {n: n, used: used, pct: pct, prior_count: prior})

        {
          status: :emitted,
          message: message,
          n: n, used: used, pct: pct,
          remaining: MAX_NUDGES - prior - 1
        }
      end

      def context(payload)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        manager = @manager || build_manager(payload)
        manager.ensure_both!

        source = payload["source"]
        injector = ContextInjector.new(manager, source: source)
        context_text = injector.generate_context

        log_activity("hook_context",
          status: context_text ? "success" : "skipped", t0: t0,
          details: {
            context_length: context_text&.length,
            context_tokens: Core::TokenEstimator.estimate(context_text),
            source: source
          })

        {status: :ok, context: context_text}
      rescue => e
        log_activity("hook_context", status: "error", t0: t0,
          details: {error: e.message})
        {status: :error, context: nil, message: e.message}
      end

      private

      def log_activity(event_type, status:, session_id: nil, t0: nil, details: nil)
        duration_ms = t0 ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round : nil
        ActivityLog.record(@store, event_type: event_type, status: status,
          session_id: session_id, duration_ms: duration_ms, details: details)
      end

      def build_manager(payload)
        project_path = payload["project_path"] || @config.project_dir
        Store::StoreManager.new(project_path: project_path, env: @env)
      end

      # Cross-scope nudge counter. Counts both stores so a user with
      # global facts only doesn't bypass the first-week limit.
      def prior_nudge_count
        manager_or_self.then do |m|
          %w[project global].sum do |scope|
            store = m.respond_to?(:store_if_exists) ? m.store_if_exists(scope) : nil
            next 0 unless store
            store.activity_events.where(event_type: "roi_nudge", status: "success").count
          end
        end
      rescue Sequel::DatabaseError
        # If we can't read the count, err on the side of "still in
        # first week" so users keep getting feedback while we figure
        # out what's wrong with the DB.
        0
      end

      # Facts whose provenance points to content_items captured in
      # this session. Active facts only — superseded/rejected ones
      # don't count as memory contributing.
      def session_contributed_facts(session_id)
        return [] unless @store
        @store.facts
          .join(:provenance, fact_id: :id)
          .join(:content_items, id: Sequel[:provenance][:content_item_id])
          .where(Sequel[:content_items][:session_id] => session_id)
          .where(Sequel[:facts][:status] => "active")
          .select(Sequel[:facts][:id])
          .distinct
          .map { |row| row[:id] }
      rescue Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("session_contributed_facts failed: #{e.message}")
        []
      end

      # Of the given fact ids, how many appear in top_fact_ids of any
      # recall or hook_context activity event tagged with this
      # session_id?
      def session_used_facts(session_id, fact_ids)
        return 0 if fact_ids.empty?
        return 0 unless @store
        target = fact_ids.to_set
        used = Set.new

        @store.activity_events
          .where(event_type: %w[recall hook_context], status: "success")
          .where(session_id: session_id)
          .select(:detail_json)
          .all
          .each do |row|
            details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
            (details["top_fact_ids"] || []).each { |id| used << id if target.include?(id) }
          end

        used.size
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("session_used_facts failed: #{e.message}")
        0
      end

      def manager_or_self
        return @manager if @manager
        # When the Handler was given only a single store (no manager),
        # we still want to count nudges; treat the store like a single-
        # scope manager via a tiny wrapper.
        @_handler_store_facade ||= SingleStoreFacade.new(@store)
      end

      class SingleStoreFacade
        def initialize(store)
          @store = store
        end

        def store_if_exists(scope)
          # The manager's store_if_exists returns nil for the absent
          # scope; we don't know which scope this single store
          # represents, so return it for "project" and nil for
          # "global". Counts undercount global-only setups, which is
          # acceptable — global-only users would normally pass a
          # manager.
          (scope == "project") ? @store : nil
        end
      end
    end
  end
end
