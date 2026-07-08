# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::Percentile do
  describe ".of" do
    it "returns 0 for an empty array" do
      expect(described_class.of([], 0.95)).to eq(0)
    end

    it "returns the nearest-rank value for p50" do
      expect(described_class.of([1, 2, 3, 4], 0.50)).to eq(2)
    end

    it "returns the top value for p95 on a small array" do
      expect(described_class.of([10, 20, 30, 40, 50], 0.95)).to eq(50)
    end

    it "returns the single element regardless of percentile" do
      expect(described_class.of([42], 0.50)).to eq(42)
      expect(described_class.of([42], 0.95)).to eq(42)
    end

    it "clamps a zero percentile to the first element" do
      expect(described_class.of([5, 6, 7], 0.0)).to eq(5)
    end

    it "never indexes past the end" do
      expect(described_class.of([1, 2, 3], 1.0)).to eq(3)
    end
  end
end
