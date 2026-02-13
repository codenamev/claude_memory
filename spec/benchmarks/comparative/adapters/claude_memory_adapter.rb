# frozen_string_literal: true

module ComparativeHelpers
  module Adapters
    # Wraps ClaudeMemory's full hybrid retrieval (FTS5 + embeddings + RRF).
    class ClaudeMemoryAdapter < BaseAdapter
      attr_reader :last_metrics

      def initialize
        @last_metrics = {}
        @builder = nil
        @recall = nil
        @reverse_map = {} # db_fact_id -> dataset_id
      end

      def available?
        true
      end

      def name
        "ClaudeMemory (hybrid)"
      end

      def setup(facts, dir)
        db_path = File.join(dir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(db_path))

        embedding_generator = begin
          require "claude_memory/embeddings/fastembed_adapter"
          ClaudeMemory::Embeddings::FastembedAdapter.new
        rescue LoadError
          nil
        end

        @builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(
          db_path,
          embedding_generator: embedding_generator
        )
        @builder.load_all_facts(facts)

        # Build reverse map: db_fact_id -> dataset_id
        @reverse_map = @builder.fact_id_map.invert

        @recall = ClaudeMemory::Recall.new(
          @builder.store,
          fts: @builder.fts,
          embedding_generator: embedding_generator
        )

        @last_metrics = {
          disk_bytes: File.size(db_path)
        }
      end

      def search(query, limit: 10)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        results = @recall.query_semantic(
          query,
          limit: limit,
          scope: "all",
          mode: :both
        )

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        @last_metrics = @last_metrics.merge(latency_ms: (elapsed * 1000).round(2))

        # Map database fact IDs back to dataset IDs
        results.filter_map { |r|
          next unless r.is_a?(Hash) && r[:fact]
          @reverse_map[r[:fact][:id]]
        }
      end

      def teardown
        @builder&.close
        @builder = nil
        @recall = nil
        @reverse_map = {}
      end

      def supports_e2e?
        true
      end

      def setup_for_claude(dir)
        # Copy MCP config so Claude can use memory tools
        source_config = File.join(
          File.expand_path("../../../..", __dir__),
          "..", "..", ".mcp.json"
        )
        dest_config = File.join(dir, ".mcp.json")
        FileUtils.cp(source_config, dest_config) if File.exist?(source_config)
      end
    end
  end
end
