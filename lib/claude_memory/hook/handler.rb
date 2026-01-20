# frozen_string_literal: true

module ClaudeMemory
  module Hook
    class Handler
      class PayloadError < Error; end

      DEFAULT_SWEEP_BUDGET = 5

      def initialize(store, env: ENV)
        @store = store
        @env = env
      end

      def ingest(payload)
        session_id = payload["session_id"] || @env["CLAUDE_SESSION_ID"]
        transcript_path = payload["transcript_path"] || @env["CLAUDE_TRANSCRIPT_PATH"]

        raise PayloadError, "Missing required field: session_id" if session_id.nil? || session_id.empty?
        raise PayloadError, "Missing required field: transcript_path" if transcript_path.nil? || transcript_path.empty?

        ingester = Ingest::Ingester.new(@store)
        ingester.ingest(
          source: "claude_code",
          session_id: session_id,
          transcript_path: transcript_path
        )
      end

      def sweep(payload)
        budget = payload.fetch("budget", DEFAULT_SWEEP_BUDGET).to_i
        sweeper = Sweep::Sweeper.new(@store)
        stats = sweeper.run!(budget_seconds: budget)

        {stats: stats}
      end

      def publish(payload)
        mode = payload.fetch("mode", "shared").to_sym
        since = payload["since"]

        publisher = Publish.new(@store)
        publisher.publish!(mode: mode, since: since)
      end
    end
  end
end
