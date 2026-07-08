# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::Jaccard do
  describe ".score" do
    it "is 1.0 for identical non-empty sets" do
      expect(described_class.score(Set[1, 2, 3], Set[1, 2, 3])).to eq(1.0)
    end

    it "is 0.0 for disjoint sets" do
      expect(described_class.score(Set[1, 2], Set[3, 4])).to eq(0.0)
    end

    it "computes |A∩B| / |A∪B| for partial overlap" do
      # {a,b,c} ∩ {b,c,d} = {b,c} (2); ∪ = {a,b,c,d} (4)
      expect(described_class.score(Set["a", "b", "c"], Set["b", "c", "d"])).to eq(0.5)
    end

    it "returns 0.0 when either set is empty" do
      expect(described_class.score(Set[], Set[1])).to eq(0.0)
      expect(described_class.score(Set[1], Set[])).to eq(0.0)
    end

    it "returns 0.0 when both sets are empty (no 0/0)" do
      expect(described_class.score(Set[], Set[])).to eq(0.0)
    end

    it "works with plain arrays too" do
      expect(described_class.score(%w[x y], %w[y z])).to be_within(0.001).of(1.0 / 3)
    end
  end
end
