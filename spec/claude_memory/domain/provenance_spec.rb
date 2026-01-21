# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Domain::Provenance do
  describe "#initialize" do
    it "creates a provenance record with required attributes" do
      prov = described_class.new(
        id: 1,
        fact_id: 42,
        content_item_id: 100,
        quote: "We use PostgreSQL"
      )

      expect(prov.id).to eq(1)
      expect(prov.fact_id).to eq(42)
      expect(prov.content_item_id).to eq(100)
      expect(prov.quote).to eq("We use PostgreSQL")
    end

    it "sets default strength to 'stated'" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1)
      expect(prov.strength).to eq("stated")
    end

    it "accepts optional strength" do
      prov = described_class.new(
        id: 1,
        fact_id: 1,
        content_item_id: 1,
        strength: "inferred"
      )
      expect(prov.strength).to eq("inferred")
    end

    it "accepts optional created_at" do
      prov = described_class.new(
        id: 1,
        fact_id: 1,
        content_item_id: 1,
        created_at: "2024-01-01"
      )
      expect(prov.created_at).to eq("2024-01-01")
    end

    it "freezes the object" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1)
      expect(prov).to be_frozen
    end

    it "raises error for missing fact_id" do
      expect {
        described_class.new(id: 1, content_item_id: 1)
      }.to raise_error(ArgumentError, "fact_id required")
    end

    it "raises error for missing content_item_id" do
      expect {
        described_class.new(id: 1, fact_id: 1)
      }.to raise_error(ArgumentError, "content_item_id required")
    end
  end

  describe "#stated?" do
    it "returns true for stated strength" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1, strength: "stated")
      expect(prov.stated?).to be true
    end

    it "returns false for inferred strength" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1, strength: "inferred")
      expect(prov.stated?).to be false
    end
  end

  describe "#inferred?" do
    it "returns true for inferred strength" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1, strength: "inferred")
      expect(prov.inferred?).to be true
    end

    it "returns false for stated strength" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1, strength: "stated")
      expect(prov.inferred?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      prov = described_class.new(
        id: 1,
        fact_id: 42,
        content_item_id: 100,
        quote: "We use PostgreSQL",
        strength: "stated",
        created_at: "2024-01-01"
      )

      hash = prov.to_h
      expect(hash).to eq({
        id: 1,
        fact_id: 42,
        content_item_id: 100,
        quote: "We use PostgreSQL",
        strength: "stated",
        created_at: "2024-01-01"
      })
    end

    it "includes nil values for optional attributes" do
      prov = described_class.new(id: 1, fact_id: 1, content_item_id: 1)
      hash = prov.to_h

      expect(hash[:quote]).to be_nil
      expect(hash[:created_at]).to be_nil
    end
  end
end
