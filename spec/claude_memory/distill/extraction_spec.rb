# frozen_string_literal: true

RSpec.describe ClaudeMemory::Distill::Extraction do
  describe "#empty?" do
    it "returns true when all collections are empty" do
      extraction = described_class.new
      expect(extraction.empty?).to be true
    end

    it "returns false when entities present" do
      extraction = described_class.new(entities: [{type: "db", name: "pg"}])
      expect(extraction.empty?).to be false
    end

    it "returns false when facts present" do
      extraction = described_class.new(facts: [{predicate: "uses", object: "x"}])
      expect(extraction.empty?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      extraction = described_class.new(
        entities: [{type: "db"}],
        facts: [{predicate: "uses"}]
      )
      hash = extraction.to_h
      expect(hash).to eq({
        entities: [{type: "db"}],
        facts: [{predicate: "uses"}],
        decisions: [],
        signals: []
      })
    end
  end
end
