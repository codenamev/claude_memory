# frozen_string_literal: true

module ComparativeHelpers
  module Adapters
    # ClaudeMemory's FTS5 keyword search only (no embeddings).
    # Baseline to measure embedding value-add.
    class FtsOnlyAdapter < BaseAdapter
      attr_reader :last_metrics

      def initialize
        @last_metrics = {}
        @builder = nil
        @reverse_map = {}
      end

      def available?
        true
      end

      def name
        "FTS-only"
      end

      def setup(facts, dir)
        db_path = File.join(dir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(db_path))

        # No embedding generator — FTS only
        @builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path)
        @builder.load_all_facts(facts)

        @reverse_map = @builder.fact_id_map.invert

        @last_metrics = {
          disk_bytes: File.size(db_path)
        }
      end

      def search(query, limit: 10)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        fts = ClaudeMemory::Index::LexicalFTS.new(@builder.store)
        content_ids = fts.search(query, limit: 30)

        # Map content IDs -> fact IDs via provenance
        retrieved_fact_ids = content_ids.flat_map { |cid|
          @builder.store.provenance
            .where(content_item_id: cid)
            .select_map(:fact_id)
        }.uniq

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        @last_metrics = @last_metrics.merge(latency_ms: (elapsed * 1000).round(2))

        # Map database fact IDs back to dataset IDs
        retrieved_fact_ids.first(limit).filter_map { |fid| @reverse_map[fid] }
      end

      def teardown
        @builder&.close
        @builder = nil
        @reverse_map = {}
      end
    end
  end
end
