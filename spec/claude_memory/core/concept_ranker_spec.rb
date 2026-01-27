# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/concept_ranker"

RSpec.describe ClaudeMemory::Core::ConceptRanker do
  describe ".rank_by_concepts" do
    it "returns empty array when no facts match all concepts" do
      concept_results = [
        [{fact: {id: 1}, receipts: [], source: :project, similarity: 0.9}],
        [{fact: {id: 2}, receipts: [], source: :project, similarity: 0.8}]
      ]

      result = described_class.rank_by_concepts(concept_results, 10)
      expect(result).to eq([])
    end

    it "returns facts that match all concepts" do
      concept_results = [
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.9},
          {fact: {id: 2}, receipts: [:r2], source: :project, similarity: 0.7}
        ],
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.8},
          {fact: {id: 3}, receipts: [:r3], source: :project, similarity: 0.6}
        ]
      ]

      result = described_class.rank_by_concepts(concept_results, 10)

      expect(result.size).to eq(1)
      expect(result[0][:fact][:id]).to eq(1)
      expect(result[0][:similarity]).to be_within(0.001).of(0.85) # Average of 0.9 and 0.8
      expect(result[0][:concept_similarities]).to eq([0.9, 0.8])
    end

    it "ranks by average similarity (highest first)" do
      concept_results = [
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.9},
          {fact: {id: 2}, receipts: [:r2], source: :project, similarity: 0.5}
        ],
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.7},
          {fact: {id: 2}, receipts: [:r2], source: :project, similarity: 0.9}
        ]
      ]

      result = described_class.rank_by_concepts(concept_results, 10)

      expect(result.size).to eq(2)
      expect(result[0][:fact][:id]).to eq(1) # Average: 0.8
      expect(result[0][:similarity]).to eq(0.8)
      expect(result[1][:fact][:id]).to eq(2) # Average: 0.7
      expect(result[1][:similarity]).to eq(0.7)
    end

    it "respects the limit parameter" do
      concept_results = [
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.9},
          {fact: {id: 2}, receipts: [:r2], source: :project, similarity: 0.8},
          {fact: {id: 3}, receipts: [:r3], source: :project, similarity: 0.7}
        ],
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.9},
          {fact: {id: 2}, receipts: [:r2], source: :project, similarity: 0.8},
          {fact: {id: 3}, receipts: [:r3], source: :project, similarity: 0.7}
        ]
      ]

      result = described_class.rank_by_concepts(concept_results, 2)

      expect(result.size).to eq(2)
      expect(result[0][:fact][:id]).to eq(1)
      expect(result[1][:fact][:id]).to eq(2)
    end

    it "handles missing similarity values (treats as 0.0)" do
      concept_results = [
        [
          {fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.9}
        ],
        [
          {fact: {id: 1}, receipts: [:r1], source: :project} # Missing similarity
        ]
      ]

      result = described_class.rank_by_concepts(concept_results, 10)

      expect(result.size).to eq(1)
      expect(result[0][:similarity]).to eq(0.45) # Average of 0.9 and 0.0
      expect(result[0][:concept_similarities]).to eq([0.9, 0.0])
    end

    it "preserves fact, receipts, and source from first match" do
      concept_results = [
        [
          {fact: {id: 1, name: "Fact 1"}, receipts: [:r1, :r2], source: :project, similarity: 0.9}
        ],
        [
          {fact: {id: 1, name: "Different data"}, receipts: [:r3], source: :global, similarity: 0.8}
        ]
      ]

      result = described_class.rank_by_concepts(concept_results, 10)

      expect(result[0][:fact][:name]).to eq("Fact 1")
      expect(result[0][:receipts]).to eq([:r1, :r2])
      expect(result[0][:source]).to eq(:project)
    end

    it "handles three or more concepts" do
      concept_results = [
        [{fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.9}],
        [{fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.8}],
        [{fact: {id: 1}, receipts: [:r1], source: :project, similarity: 0.7}]
      ]

      result = described_class.rank_by_concepts(concept_results, 10)

      expect(result.size).to eq(1)
      expect(result[0][:similarity]).to be_within(0.001).of(0.8) # Average of 0.9, 0.8, 0.7
      expect(result[0][:concept_similarities]).to eq([0.9, 0.8, 0.7])
    end
  end
end
