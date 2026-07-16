# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::TokenBudget do
  describe ".from_detail_json" do
    it "keeps only positive-integer context_tokens" do
      json = [
        {context_tokens: 100}.to_json,
        {context_tokens: 300}.to_json,
        {context_tokens: 0}.to_json,      # dropped (not > 0)
        {context_tokens: "big"}.to_json,  # dropped (not Integer)
        {other: 1}.to_json,               # dropped (no key)
        nil                               # dropped (nil json)
      ]
      budget = described_class.from_detail_json(json)
      expect(budget.sorted).to eq([100, 300])
    end
  end

  describe "aggregates" do
    subject(:budget) { described_class.new([300, 100, 200, 500]) }

    it "sorts the tokens" do
      expect(budget.sorted).to eq([100, 200, 300, 500])
    end

    it "reports sample size, min, max, avg" do
      expect(budget.sample_size).to eq(4)
      expect(budget.min).to eq(100)
      expect(budget.max).to eq(500)
      expect(budget.avg).to eq(275)
    end

    it "computes percentiles via Core::Percentile" do
      expect(budget.p50).to eq(200)
      expect(budget.p95).to eq(500)
    end
  end

  describe "empty" do
    subject(:budget) { described_class.new([]) }

    it "is empty with zeroed aggregates" do
      expect(budget).to be_empty
      expect(budget.sample_size).to eq(0)
      expect(budget.avg).to eq(0)
      expect(budget.p50).to eq(0)
    end

    it "returns 0 (not nil) for min and max, matching the other aggregates" do
      expect(budget.min).to eq(0)
      expect(budget.max).to eq(0)
    end

    it "is frozen" do
      expect(budget).to be_frozen
    end
  end
end
