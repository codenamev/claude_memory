# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/result_builder"

RSpec.describe ClaudeMemory::Core::ResultBuilder do
  describe ".build_results" do
    let(:fact_ids) { [1, 2, 3] }
    let(:facts_by_id) do
      {
        1 => {id: 1, predicate: "uses", object_literal: "Ruby"},
        2 => {id: 2, predicate: "prefers", object_literal: "TDD"},
        3 => {id: 3, predicate: "likes", object_literal: "Rails"}
      }
    end
    let(:receipts_by_fact_id) do
      {
        1 => [{quote: "We use Ruby", strength: "stated"}],
        2 => [{quote: "I prefer TDD", strength: "stated"}]
        # Note: fact 3 has no receipts
      }
    end

    it "builds results for all fact_ids with facts" do
      results = described_class.build_results(
        fact_ids,
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results.length).to eq(3)
      expect(results[0][:fact][:id]).to eq(1)
      expect(results[1][:fact][:id]).to eq(2)
      expect(results[2][:fact][:id]).to eq(3)
    end

    it "includes receipts when available" do
      results = described_class.build_results(
        [1],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results[0][:receipts]).to eq([{quote: "We use Ruby", strength: "stated"}])
    end

    it "uses empty array for missing receipts" do
      results = described_class.build_results(
        [3],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results[0][:receipts]).to eq([])
    end

    it "includes source in results" do
      results = described_class.build_results(
        [1],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :global
      )

      expect(results[0][:source]).to eq(:global)
    end

    it "includes similarity when provided" do
      results = described_class.build_results(
        [1],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project,
        similarity: 0.85
      )

      expect(results[0][:similarity]).to eq(0.85)
    end

    it "omits similarity when nil" do
      results = described_class.build_results(
        [1],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results[0]).not_to have_key(:similarity)
    end

    it "skips fact_ids with no matching fact" do
      results = described_class.build_results(
        [1, 999],  # 999 doesn't exist
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results.length).to eq(1)
      expect(results[0][:fact][:id]).to eq(1)
    end

    it "handles empty fact_ids" do
      results = described_class.build_results(
        [],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results).to eq([])
    end
  end

  describe ".build_results_with_scores" do
    let(:facts_by_id) do
      {
        1 => {id: 1, predicate: "uses", object_literal: "Ruby"},
        2 => {id: 2, predicate: "prefers", object_literal: "TDD"}
      }
    end
    let(:receipts_by_fact_id) do
      {
        1 => [{quote: "We use Ruby", strength: "stated"}],
        2 => [{quote: "I prefer TDD", strength: "stated"}]
      }
    end

    it "builds results with individual similarity scores" do
      matches = [
        {fact_id: 1, similarity: 0.9},
        {fact_id: 2, similarity: 0.7}
      ]

      results = described_class.build_results_with_scores(
        matches,
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results.length).to eq(2)
      expect(results[0][:similarity]).to eq(0.9)
      expect(results[1][:similarity]).to eq(0.7)
    end

    it "handles matches with nested candidate hash" do
      matches = [
        {candidate: {fact_id: 1}, similarity: 0.9}
      ]

      results = described_class.build_results_with_scores(
        matches,
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results.length).to eq(1)
      expect(results[0][:fact][:id]).to eq(1)
      expect(results[0][:similarity]).to eq(0.9)
    end

    it "skips matches with no fact_id" do
      matches = [
        {similarity: 0.9}  # No fact_id
      ]

      results = described_class.build_results_with_scores(
        matches,
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results).to eq([])
    end

    it "skips matches with missing facts" do
      matches = [
        {fact_id: 999, similarity: 0.9}  # Fact doesn't exist
      ]

      results = described_class.build_results_with_scores(
        matches,
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results).to eq([])
    end

    it "includes facts, receipts, and source" do
      matches = [{fact_id: 1, similarity: 0.9}]

      results = described_class.build_results_with_scores(
        matches,
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :global
      )

      expect(results[0][:fact]).to eq({id: 1, predicate: "uses", object_literal: "Ruby"})
      expect(results[0][:receipts]).to eq([{quote: "We use Ruby", strength: "stated"}])
      expect(results[0][:source]).to eq(:global)
    end

    it "handles empty matches" do
      results = described_class.build_results_with_scores(
        [],
        facts_by_id: facts_by_id,
        receipts_by_fact_id: receipts_by_fact_id,
        source: :project
      )

      expect(results).to eq([])
    end
  end
end
