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

        log_activity("hook_sweep", status: "success", t0: t0,
          details: {elapsed_seconds: stats[:elapsed_seconds],
                    budget_honored: stats[:budget_honored]})

        {stats: stats}
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

      def context(payload)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        manager = @manager || build_manager(payload)
        manager.ensure_both!

        source = payload["source"]
        injector = ContextInjector.new(manager, source: source)
        context_text = injector.generate_context

        log_activity("hook_context",
          status: context_text ? "success" : "skipped", t0: t0,
          details: {context_length: context_text&.length, source: source})

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
    end
  end
end
