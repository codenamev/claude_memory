# frozen_string_literal: true

module ComparativeHelpers
  module Adapters
    # Baseline: no memory system at all. Always returns empty results.
    class NoMemoryAdapter < BaseAdapter
      def available?
        true
      end

      def name
        "No memory"
      end

      def setup(facts, dir)
        # No-op
      end

      def search(query, limit: 10)
        []
      end

      def last_metrics
        {latency_ms: 0.0, disk_bytes: 0}
      end

      def teardown
      end

      def supports_e2e?
        true
      end

      def setup_for_claude(dir)
        # Clean tmpdir with no memory — no-op
      end
    end
  end
end
