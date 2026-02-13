# frozen_string_literal: true

module ComparativeHelpers
  module Adapters
    # Abstract interface for comparative benchmark adapters.
    # Each adapter wraps a different memory tool and normalizes
    # its output to canonical dataset IDs for fair comparison.
    class BaseAdapter
      # Is this tool installed and ready to use?
      def available?
        raise NotImplementedError, "#{self.class}#available?"
      end

      # Human-readable name for reports
      def name
        raise NotImplementedError, "#{self.class}#name"
      end

      # Load canonical knowledge items into the tool's native format.
      # @param facts [Array<Hash>] facts from facts.yml dataset
      # @param dir [String] working directory for this adapter's data
      def setup(facts, dir)
        raise NotImplementedError, "#{self.class}#setup"
      end

      # Search for facts matching query.
      # @param query [String] natural language query
      # @param limit [Integer] max results
      # @return [Array<String>] canonical dataset IDs (e.g., "ts_db_001")
      def search(query, limit: 10)
        raise NotImplementedError, "#{self.class}#search"
      end

      # Metrics from the last search() call.
      # @return [Hash] { latency_ms: Float, disk_bytes: Integer }
      def last_metrics
        {}
      end

      # Clean up resources
      def teardown
      end

      # Configure the tool so `claude -p` can use it in the given directory.
      # Only needed for adapters that support E2E testing.
      # @param dir [String] working directory where claude will run
      def setup_for_claude(dir)
      end

      # Whether this adapter supports E2E testing with real Claude.
      def supports_e2e?
        false
      end
    end
  end
end
