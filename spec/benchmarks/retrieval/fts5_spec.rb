# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "FTS5 Retrieval Accuracy", :benchmark do
  include BenchmarkHelpers::IRMetrics
  include BenchmarkHelpers::BenchmarkSetup

  let(:builder) { BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path) }

  let(:fts5_queries) do
    all_queries.select { |q| q["tests"]&.include?("fts5") }
  end

  before do
    builder.load_all_facts(all_facts)
  end

  after do
    builder.close
  end

  describe "retrieval metrics by difficulty" do
    %w[easy medium hard abstention temporal].each do |difficulty|
      context "#{difficulty} queries" do
        let(:queries_for_difficulty) do
          fts5_queries.select { |q| q["difficulty"] == difficulty }
        end

        it "measures Recall@5, Recall@10, and MRR" do
          skip "No #{difficulty} FTS5 queries" if queries_for_difficulty.empty?

          recall5_scores = []
          recall10_scores = []
          mrr_scores = []

          queries_for_difficulty.each do |query_data|
            # Run FTS5 search
            fts = ClaudeMemory::Index::LexicalFTS.new(builder.store)
            content_ids = fts.search(query_data["query"], limit: 30)

            # Map content IDs to fact IDs via provenance
            retrieved_fact_ids = content_ids.flat_map do |cid|
              builder.store.provenance
                .where(content_item_id: cid)
                .select_map(:fact_id)
            end.uniq

            # Resolve expected dataset IDs to database IDs
            expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
            excluded_db_ids = builder.resolve_ids(query_data["excluded_facts"] || [])

            if difficulty == "abstention"
              # For abstention, fewer results is better
              # We don't have a good way to check "no relevant results" at FTS level
              # since FTS returns keyword matches, so we just track the count
              metrics.record(difficulty, "result_count", retrieved_fact_ids.size)
            elsif difficulty == "temporal"
              # For temporal, check that excluded (superseded) facts don't appear before expected
              excluded_positions = excluded_db_ids.filter_map { |id| retrieved_fact_ids.index(id) }
              expected_positions = expected_db_ids.filter_map { |id| retrieved_fact_ids.index(id) }

              # Score: 1.0 if expected appears and excluded doesn't, or expected appears first
              if expected_positions.any?
                if excluded_positions.empty? || expected_positions.min < excluded_positions.min
                  metrics.record(difficulty, "temporal_correct", 1.0)
                else
                  metrics.record(difficulty, "temporal_correct", 0.0)
                end
              else
                metrics.record(difficulty, "temporal_correct", 0.0)
              end
            else
              # Standard retrieval metrics
              r5 = recall_at_k(retrieved_fact_ids, expected_db_ids, 5)
              r10 = recall_at_k(retrieved_fact_ids, expected_db_ids, 10)
              m = mrr(retrieved_fact_ids, expected_db_ids)

              recall5_scores << r5
              recall10_scores << r10
              mrr_scores << m

              metrics.record(difficulty, "Recall@5", r5)
              metrics.record(difficulty, "Recall@10", r10)
              metrics.record(difficulty, "MRR", m)
            end
          end

          # Report aggregate for this difficulty level
          unless difficulty == "abstention" || difficulty == "temporal"
            avg_r5 = recall5_scores.empty? ? 0.0 : recall5_scores.sum / recall5_scores.size
            avg_r10 = recall10_scores.empty? ? 0.0 : recall10_scores.sum / recall10_scores.size
            avg_mrr = mrr_scores.empty? ? 0.0 : mrr_scores.sum / mrr_scores.size

            puts "  FTS5 #{difficulty}: Recall@5=#{avg_r5.round(3)} Recall@10=#{avg_r10.round(3)} MRR=#{avg_mrr.round(3)} (#{queries_for_difficulty.size} queries)"

            # Soft assertions - we track metrics but don't fail on specific thresholds
            # This lets us establish baselines before setting targets
            expect(recall5_scores).not_to be_empty, "Should have measurable recall scores"
          end
        end
      end
    end
  end

  describe "aggregate FTS5 performance" do
    it "reports overall metrics across all difficulties" do
      all_recall5 = []
      all_mrr = []

      fts5_queries.each do |query_data|
        next if query_data["difficulty"] == "abstention"
        next if query_data["difficulty"] == "temporal"

        fts = ClaudeMemory::Index::LexicalFTS.new(builder.store)
        content_ids = fts.search(query_data["query"], limit: 30)

        retrieved_fact_ids = content_ids.flat_map do |cid|
          builder.store.provenance
            .where(content_item_id: cid)
            .select_map(:fact_id)
        end.uniq

        expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
        next if expected_db_ids.empty?

        all_recall5 << recall_at_k(retrieved_fact_ids, expected_db_ids, 5)
        all_mrr << mrr(retrieved_fact_ids, expected_db_ids)
      end

      avg_recall5 = all_recall5.empty? ? 0.0 : all_recall5.sum / all_recall5.size
      avg_mrr = all_mrr.empty? ? 0.0 : all_mrr.sum / all_mrr.size

      puts "\n  FTS5 AGGREGATE: Recall@5=#{avg_recall5.round(3)} MRR=#{avg_mrr.round(3)} (#{all_recall5.size} queries)"

      expect(all_recall5).not_to be_empty
    end
  end
end
