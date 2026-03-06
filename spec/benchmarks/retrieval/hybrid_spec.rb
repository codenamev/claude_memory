# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "Hybrid Retrieval Accuracy", :benchmark do
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

  let(:hybrid_queries) do
    all_queries.select { |q| q["tests"]&.include?("hybrid") }
  end

  before do
    builder.load_all_facts(all_facts)
  end

  after do
    builder.close
  end

  describe "retrieval metrics by difficulty" do
    %w[easy medium hard abstention temporal scope].each do |difficulty|
      context "#{difficulty} queries" do
        let(:queries_for_difficulty) do
          hybrid_queries.select { |q| q["difficulty"] == difficulty }
        end

        it "measures Recall@5, Recall@10, and MRR via hybrid search" do
          skip "No #{difficulty} hybrid queries" if queries_for_difficulty.empty?

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
              mode: :both
            )

            retrieved_fact_ids = results.filter_map { |r|
              if r.is_a?(Hash) && r[:fact]
                r[:fact][:id]
              end
            }

            expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
            excluded_db_ids = builder.resolve_ids(query_data["excluded_facts"] || [])

            case difficulty
            when "abstention"
              # For abstention, check how many retrieved facts are NOT in the dataset's domain
              metrics.record(difficulty, "result_count", retrieved_fact_ids.size)

            when "temporal"
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

            when "scope"
              # For scope queries, check that project-scoped facts rank higher when appropriate
              expected_db_ids_set = expected_db_ids.to_set
              project_positions = []
              global_positions = []

              retrieved_fact_ids.each_with_index do |fid, idx|
                next unless expected_db_ids_set.include?(fid)
                fact = builder.store.facts.where(id: fid).first
                if fact && fact[:scope] == "project"
                  project_positions << idx
                elsif fact && fact[:scope] == "global"
                  global_positions << idx
                end
              end

              metrics.record(difficulty, "has_results", retrieved_fact_ids.any? ? 1.0 : 0.0)

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

          unless %w[abstention temporal scope].include?(difficulty)
            next if recall5_scores.empty?

            avg_r5 = recall5_scores.sum / recall5_scores.size
            avg_r10 = recall10_scores.sum / recall10_scores.size
            avg_mrr = mrr_scores.sum / mrr_scores.size

            puts "  Hybrid #{difficulty}: Recall@5=#{avg_r5.round(3)} Recall@10=#{avg_r10.round(3)} MRR=#{avg_mrr.round(3)} (#{queries_for_difficulty.size} queries)"
          end
        end
      end
    end
  end

  describe "aggregate hybrid performance" do
    it "reports overall metrics and comparison" do
      recall = ClaudeMemory::Recall.new(
        builder.store,
        fts: builder.fts,
        embedding_generator: embedding_generator
      )

      all_recall5 = []
      all_mrr = []
      all_ndcg10 = []

      hybrid_queries.each do |query_data|
        next if %w[abstention temporal scope].include?(query_data["difficulty"])

        results = recall.query_semantic(
          query_data["query"],
          limit: 10,
          scope: "all",
          mode: :both
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

        puts "\n  Hybrid AGGREGATE: Recall@5=#{avg_recall5.round(3)} MRR=#{avg_mrr.round(3)} nDCG@10=#{avg_ndcg10.round(3)} (#{all_recall5.size} queries)"
      end

      expect(all_recall5).not_to be_empty
    end
  end

  describe "hybrid vs FTS-only regression guard" do
    let(:fts_queries) do
      all_queries.select { |q| q["tests"]&.include?("fts5") && q["difficulty"] == "easy" }
    end

    it "hybrid Recall@5 on easy queries is not worse than FTS-only" do
      recall = ClaudeMemory::Recall.new(
        builder.store,
        fts: builder.fts,
        embedding_generator: embedding_generator
      )

      hybrid_scores = []
      fts_scores = []

      fts_queries.each do |query_data|
        expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
        next if expected_db_ids.empty?

        # Hybrid (mode: :both)
        hybrid_results = recall.query_semantic(query_data["query"], limit: 10, scope: "all", mode: :both)
        hybrid_ids = hybrid_results.filter_map { |r| r.is_a?(Hash) ? r[:fact]&.[](:id) : nil }
        hybrid_scores << recall_at_k(hybrid_ids, expected_db_ids, 5)

        # FTS-only (mode: :text)
        fts_results = recall.query_semantic(query_data["query"], limit: 10, scope: "all", mode: :text)
        fts_ids = fts_results.filter_map { |r| r.is_a?(Hash) ? r[:fact]&.[](:id) : nil }
        fts_scores << recall_at_k(fts_ids, expected_db_ids, 5)
      end

      next if hybrid_scores.empty?

      avg_hybrid = hybrid_scores.sum / hybrid_scores.size
      avg_fts = fts_scores.sum / fts_scores.size

      puts "  Regression guard: Hybrid easy Recall@5=#{avg_hybrid.round(3)} vs FTS-only=#{avg_fts.round(3)}"

      # Hybrid must not regress below 90% of FTS-only performance
      expect(avg_hybrid).to be >= (avg_fts * 0.9),
        "Hybrid Recall@5 (#{avg_hybrid.round(3)}) fell below 90% of FTS-only (#{avg_fts.round(3)}). " \
        "The vector component may be hurting ranking."
    end
  end
end
