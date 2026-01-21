# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Domain::Conflict do
  describe "#initialize" do
    it "creates a conflict with required attributes" do
      conflict = described_class.new(
        id: 1,
        fact_a_id: 10,
        fact_b_id: 20
      )

      expect(conflict.id).to eq(1)
      expect(conflict.fact_a_id).to eq(10)
      expect(conflict.fact_b_id).to eq(20)
    end

    it "sets default status to 'open'" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2)
      expect(conflict.status).to eq("open")
    end

    it "accepts optional attributes" do
      conflict = described_class.new(
        id: 1,
        fact_a_id: 10,
        fact_b_id: 20,
        status: "resolved",
        notes: "User chose fact A",
        detected_at: "2024-01-01",
        resolved_at: "2024-01-02"
      )

      expect(conflict.status).to eq("resolved")
      expect(conflict.notes).to eq("User chose fact A")
      expect(conflict.detected_at).to eq("2024-01-01")
      expect(conflict.resolved_at).to eq("2024-01-02")
    end

    it "freezes the object" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2)
      expect(conflict).to be_frozen
    end

    it "raises error for missing fact_a_id" do
      expect {
        described_class.new(id: 1, fact_b_id: 2)
      }.to raise_error(ArgumentError, "fact_a_id required")
    end

    it "raises error for missing fact_b_id" do
      expect {
        described_class.new(id: 1, fact_a_id: 1)
      }.to raise_error(ArgumentError, "fact_b_id required")
    end
  end

  describe "#open?" do
    it "returns true for open status" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2, status: "open")
      expect(conflict.open?).to be true
    end

    it "returns false for resolved status" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2, status: "resolved")
      expect(conflict.open?).to be false
    end
  end

  describe "#resolved?" do
    it "returns true for resolved status" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2, status: "resolved")
      expect(conflict.resolved?).to be true
    end

    it "returns false for open status" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2, status: "open")
      expect(conflict.resolved?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      conflict = described_class.new(
        id: 1,
        fact_a_id: 10,
        fact_b_id: 20,
        status: "resolved",
        notes: "Resolved by user",
        detected_at: "2024-01-01",
        resolved_at: "2024-01-02"
      )

      hash = conflict.to_h
      expect(hash).to eq({
        id: 1,
        fact_a_id: 10,
        fact_b_id: 20,
        status: "resolved",
        notes: "Resolved by user",
        detected_at: "2024-01-01",
        resolved_at: "2024-01-02"
      })
    end

    it "includes nil values for optional attributes" do
      conflict = described_class.new(id: 1, fact_a_id: 1, fact_b_id: 2)
      hash = conflict.to_h

      expect(hash[:notes]).to be_nil
      expect(hash[:detected_at]).to be_nil
      expect(hash[:resolved_at]).to be_nil
    end
  end
end
