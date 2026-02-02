# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "Semantic Retrieval Accuracy", :benchmark do
  include BenchmarkHelpers::IRMetrics
  include BenchmarkHelpers::BenchmarkSetup

  let(:embedding_generator) do
    require "claude_memory/embeddings/fastembed_adapter"
    ClaudeMemory::Embeddings::FastembedAdapter.new
  rescue LoadError
    skip "fastembed gem not available -- install with: gem install fastembed"
  end

  let(:builder) do
    BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path, embedding_generator: embedding_generator)
  end

  let(:semantic_queries) do
    all_queries.select { |q| q["tests"]&.include?("semantic") }
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
          semantic_queries.select { |q| q["difficulty"] == difficulty }
        end

        it "measures Recall@5, Recall@10, and MRR via vector search" do
          skip "No #{difficulty} semantic queries" if queries_for_difficulty.empty?

          recall = ClaudeMemory::Recall.new(
            builder.store,
            fts: builder.fts,
            embedding_generator: embedding_generator
          )

          recall5_scores = []
          recall10_scores = []
          mrr_scores = []

          queries_for_difficulty.each do |query_data|
            results = recall.query_semantic(
              query_data["query"],
              limit: 10,
              scope: "all",
              mode: :vector
            )

            retrieved_fact_ids = results.filter_map { |r|
              r.is_a?(Hash) ? r[:fact]&.[](:id) : nil
            }

            expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
            excluded_db_ids = builder.resolve_ids(query_data["excluded_facts"] || [])

            if difficulty == "abstention"
              metrics.record(difficulty, "result_count", retrieved_fact_ids.size)
            elsif difficulty == "temporal"
              excluded_positions = excluded_db_ids.filter_map { |id| retrieved_fact_ids.index(id) }
              expected_positions = expected_db_ids.filter_map { |id| retrieved_fact_ids.index(id) }

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

          unless difficulty == "abstention" || difficulty == "temporal"
            next if recall5_scores.empty?

            avg_r5 = recall5_scores.sum / recall5_scores.size
            avg_r10 = recall10_scores.sum / recall10_scores.size
            avg_mrr = mrr_scores.sum / mrr_scores.size

            puts "  Semantic #{difficulty}: Recall@5=#{avg_r5.round(3)} Recall@10=#{avg_r10.round(3)} MRR=#{avg_mrr.round(3)} (#{queries_for_difficulty.size} queries)"
          end
        end
      end
    end
  end

  describe "aggregate semantic performance" do
    it "reports overall metrics across all difficulties" do
      recall = ClaudeMemory::Recall.new(
        builder.store,
        fts: builder.fts,
        embedding_generator: embedding_generator
      )

      all_recall5 = []
      all_mrr = []
      all_ndcg10 = []

      semantic_queries.each do |query_data|
        next if query_data["difficulty"] == "abstention"
        next if query_data["difficulty"] == "temporal"

        results = recall.query_semantic(
          query_data["query"],
          limit: 10,
          scope: "all",
          mode: :vector
        )

        retrieved_fact_ids = results.filter_map { |r|
          r.is_a?(Hash) ? r[:fact]&.[](:id) : nil
        }

        expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
        next if expected_db_ids.empty?

        all_recall5 << recall_at_k(retrieved_fact_ids, expected_db_ids, 5)
        all_mrr << mrr(retrieved_fact_ids, expected_db_ids)
        all_ndcg10 << ndcg_at_k(retrieved_fact_ids, expected_db_ids, 10)
      end

      if all_recall5.any?
        avg_recall5 = all_recall5.sum / all_recall5.size
        avg_mrr = all_mrr.sum / all_mrr.size
        avg_ndcg10 = all_ndcg10.sum / all_ndcg10.size

        puts "\n  Semantic AGGREGATE: Recall@5=#{avg_recall5.round(3)} MRR=#{avg_mrr.round(3)} nDCG@10=#{avg_ndcg10.round(3)} (#{all_recall5.size} queries)"
      end

      expect(all_recall5).not_to be_empty, "Semantic search should return results with FastEmbed embeddings"
    end
  end
end
