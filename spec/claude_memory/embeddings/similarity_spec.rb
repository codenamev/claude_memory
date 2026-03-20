# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Embeddings::Similarity do
  describe ".cosine" do
    it "returns 1.0 for identical normalized vectors" do
      vec = [0.5, 0.5, 0.5, 0.5]
      expect(described_class.cosine(vec, vec)).to be_within(0.01).of(1.0)
    end

    it "returns 0.0 for orthogonal vectors" do
      vec_a = [1.0, 0.0]
      vec_b = [0.0, 1.0]
      expect(described_class.cosine(vec_a, vec_b)).to eq(0.0)
    end

    it "returns 0.0 for nil inputs" do
      expect(described_class.cosine(nil, [1.0])).to eq(0.0)
      expect(described_class.cosine([1.0], nil)).to eq(0.0)
    end

    it "returns 0.0 for empty inputs" do
      expect(described_class.cosine([], [1.0])).to eq(0.0)
      expect(described_class.cosine([1.0], [])).to eq(0.0)
    end

    it "clamps result to [0, 1]" do
      result = described_class.cosine([1.0, 0.0], [0.5, 0.5])
      expect(result).to be >= 0.0
      expect(result).to be <= 1.0
    end
  end

  describe ".top_k" do
    let(:query) { [1.0, 0.0, 0.0] }
    let(:candidates) do
      [
        {embedding: [0.1, 0.9, 0.0], id: 1},
        {embedding: [0.9, 0.1, 0.0], id: 2},
        {embedding: [0.5, 0.5, 0.0], id: 3}
      ]
    end

    it "returns top K candidates sorted by similarity" do
      results = described_class.top_k(query, candidates, 2)
      expect(results.size).to eq(2)
      expect(results.first[:candidate][:id]).to eq(2)
    end

    it "returns empty array for empty candidates" do
      expect(described_class.top_k(query, [], 5)).to eq([])
    end

    it "includes similarity scores" do
      results = described_class.top_k(query, candidates, 3)
      results.each do |r|
        expect(r).to have_key(:similarity)
        expect(r[:similarity]).to be_a(Float)
      end
    end
  end

  describe ".average_similarity" do
    it "computes average of cosine similarities" do
      query = [1.0, 0.0]
      targets = [[1.0, 0.0], [0.0, 1.0]]
      result = described_class.average_similarity(query, targets)
      expect(result).to be_within(0.01).of(0.5)
    end

    it "returns 0.0 for empty targets" do
      expect(described_class.average_similarity([1.0], [])).to eq(0.0)
    end
  end

  describe ".batch_similarities" do
    it "returns similarities in candidate order" do
      query = [1.0, 0.0]
      candidates = [[1.0, 0.0], [0.0, 1.0], [0.5, 0.5]]
      results = described_class.batch_similarities(query, candidates)

      expect(results.size).to eq(3)
      expect(results[0]).to be_within(0.01).of(1.0)
      expect(results[1]).to eq(0.0)
    end
  end
end
