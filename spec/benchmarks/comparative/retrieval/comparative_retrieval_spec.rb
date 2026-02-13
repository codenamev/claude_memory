# frozen_string_literal: true

require_relative "../comparative_helper"

RSpec.describe "Comparative Retrieval Accuracy", :comparative, :benchmark do
  include BenchmarkHelpers::IRMetrics
  include ComparativeHelpers::ComparativeSetup

  let(:adapters) { ComparativeHelpers.retrieval_adapters }

  before do
    adapters.each do |adapter|
      dir = adapter_dir(adapter)
      adapter.setup(all_facts, dir)
    end
  end

  after do
    adapters.each(&:teardown)
  end

  describe "head-to-head retrieval by difficulty" do
    %w[easy medium hard].each do |difficulty|
      context "#{difficulty} queries" do
        let(:queries_for_difficulty) do
          comparative_queries.select { |q| q["difficulty"] == difficulty }
        end

        it "compares retrieval metrics across all available adapters" do
          skip "No #{difficulty} queries in comparative subset" if queries_for_difficulty.empty?

          adapter_scores = {}
          adapters.each { |a| adapter_scores[a.name] = {recall_5: [], recall_10: [], mrr: [], ndcg_10: []} }

          queries_for_difficulty.each do |query_data|
            expected_ids = query_data["expected_facts"] || []
            next if expected_ids.empty?

            adapters.each do |adapter|
              retrieved_ids = adapter.search(query_data["query"], limit: 10)

              r5 = recall_at_k(retrieved_ids, expected_ids, 5)
              r10 = recall_at_k(retrieved_ids, expected_ids, 10)
              m = mrr(retrieved_ids, expected_ids)
              ndcg = ndcg_at_k(retrieved_ids, expected_ids, 10)

              adapter_scores[adapter.name][:recall_5] << r5
              adapter_scores[adapter.name][:recall_10] << r10
              adapter_scores[adapter.name][:mrr] << m
              adapter_scores[adapter.name][:ndcg_10] << ndcg
            end
          end

          # Aggregate and report
          adapters.each do |adapter|
            scores = adapter_scores[adapter.name]
            next if scores[:recall_5].empty?

            avg = ->(arr) { arr.sum / arr.size.to_f }

            reporter.add_retrieval_results(adapter.name, difficulty, {
              recall_5: avg.call(scores[:recall_5]),
              recall_10: avg.call(scores[:recall_10]),
              mrr: avg.call(scores[:mrr]),
              ndcg_10: avg.call(scores[:ndcg_10]),
              query_count: scores[:recall_5].size
            })

            puts "  #{adapter.name} #{difficulty}: " \
              "Recall@5=#{avg.call(scores[:recall_5]).round(3)} " \
              "MRR=#{avg.call(scores[:mrr]).round(3)} " \
              "(#{scores[:recall_5].size} queries)"
          end

          # Soft assertion: at least one adapter should have results
          has_results = adapter_scores.any? { |_, s| s[:recall_5].any? }
          expect(has_results).to be(true), "At least one adapter should produce retrieval results"
        end
      end
    end
  end

  describe "aggregate comparative performance" do
    it "reports overall metrics across all difficulties" do
      adapter_scores = {}
      adapters.each { |a| adapter_scores[a.name] = {recall_5: [], mrr: [], ndcg_10: []} }

      comparative_queries.each do |query_data|
        next if %w[abstention temporal scope].include?(query_data["difficulty"])

        expected_ids = query_data["expected_facts"] || []
        next if expected_ids.empty?

        adapters.each do |adapter|
          retrieved_ids = adapter.search(query_data["query"], limit: 10)

          adapter_scores[adapter.name][:recall_5] << recall_at_k(retrieved_ids, expected_ids, 5)
          adapter_scores[adapter.name][:mrr] << mrr(retrieved_ids, expected_ids)
          adapter_scores[adapter.name][:ndcg_10] << ndcg_at_k(retrieved_ids, expected_ids, 10)
        end
      end

      puts "\n  AGGREGATE COMPARATIVE RETRIEVAL:"
      adapters.each do |adapter|
        scores = adapter_scores[adapter.name]
        next if scores[:recall_5].empty?

        avg = ->(arr) { arr.sum / arr.size.to_f }
        puts "    #{adapter.name}: " \
          "Recall@5=#{avg.call(scores[:recall_5]).round(3)} " \
          "MRR=#{avg.call(scores[:mrr]).round(3)} " \
          "nDCG@10=#{avg.call(scores[:ndcg_10]).round(3)} " \
          "(#{scores[:recall_5].size} queries)"
      end

      # Print formatted report
      puts reporter.terminal_report

      expect(adapter_scores).not_to be_empty
    end
  end
end
