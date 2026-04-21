# frozen_string_literal: true

require_relative "benchmark_helper"

RSpec.describe BenchmarkHelpers::RelevanceMetrics, :benchmark do
  let(:dummy) { Class.new { include BenchmarkHelpers::RelevanceMetrics }.new }

  describe "#relevance_ratio" do
    it "returns 1.0 when nothing was injected (no signal either way)" do
      expect(dummy.relevance_ratio([], "any response text")).to eq(1.0)
    end

    it "returns 1.0 when every injected subject appears in the response" do
      subjects = ["ContextInjector", "PredicatePolicy"]
      response = "The ContextInjector uses PredicatePolicy for vocabulary."
      expect(dummy.relevance_ratio(subjects, response)).to eq(1.0)
    end

    it "returns 0.0 when no injected subject is referenced" do
      expect(dummy.relevance_ratio(%w[Foo Bar], "Totally unrelated text.")).to eq(0.0)
    end

    it "returns 0.5 on half-hit" do
      subjects = %w[Alpha Beta]
      response = "Alpha only"
      expect(dummy.relevance_ratio(subjects, response)).to eq(0.5)
    end

    it "is case-insensitive" do
      expect(dummy.relevance_ratio(["Rails"], "we use rails for web")).to eq(1.0)
    end

    it "deduplicates injected subjects so repeats don't double-count" do
      expect(dummy.relevance_ratio(%w[Foo Foo Bar], "Foo present")).to eq(0.5)
    end

    it "ignores nil and empty subjects" do
      expect(dummy.relevance_ratio([nil, "", "Present"], "Present here")).to eq(1.0)
    end
  end
end
