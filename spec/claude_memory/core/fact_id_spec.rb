# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::FactId do
  describe "#initialize" do
    it "accepts a positive integer" do
      fact_id = described_class.new(42)
      expect(fact_id.value).to eq(42)
    end

    it "converts string to integer" do
      fact_id = described_class.new("123")
      expect(fact_id.value).to eq(123)
    end

    it "raises error for zero" do
      expect { described_class.new(0) }.to raise_error(ArgumentError, "Fact ID must be a positive integer")
    end

    it "raises error for negative integer" do
      expect { described_class.new(-5) }.to raise_error(ArgumentError, "Fact ID must be a positive integer")
    end

    it "raises error for nil" do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, "Fact ID must be a positive integer")
    end

    it "raises error for non-numeric string" do
      expect { described_class.new("abc") }.to raise_error(ArgumentError, "Fact ID must be a positive integer")
    end

    it "freezes the object" do
      fact_id = described_class.new(1)
      expect(fact_id).to be_frozen
    end
  end

  describe "#to_i" do
    it "returns the integer value" do
      fact_id = described_class.new(42)
      expect(fact_id.to_i).to eq(42)
    end
  end

  describe "#to_s" do
    it "returns the string representation" do
      fact_id = described_class.new(42)
      expect(fact_id.to_s).to eq("42")
    end
  end

  describe "#==" do
    it "returns true for same value" do
      fact_id1 = described_class.new(1)
      fact_id2 = described_class.new(1)
      expect(fact_id1).to eq(fact_id2)
    end

    it "returns false for different values" do
      fact_id1 = described_class.new(1)
      fact_id2 = described_class.new(2)
      expect(fact_id1).not_to eq(fact_id2)
    end

    it "returns false for different types" do
      fact_id = described_class.new(1)
      expect(fact_id).not_to eq(1)
    end
  end

  describe "#eql?" do
    it "behaves like ==" do
      fact_id1 = described_class.new(1)
      fact_id2 = described_class.new(1)
      expect(fact_id1.eql?(fact_id2)).to be true
    end
  end

  describe "#hash" do
    it "returns same hash for equal values" do
      fact_id1 = described_class.new(1)
      fact_id2 = described_class.new(1)
      expect(fact_id1.hash).to eq(fact_id2.hash)
    end

    it "can be used as hash key" do
      fact_id1 = described_class.new(1)
      fact_id2 = described_class.new(1)
      hash = {fact_id1 => "value"}
      expect(hash[fact_id2]).to eq("value")
    end
  end
end
