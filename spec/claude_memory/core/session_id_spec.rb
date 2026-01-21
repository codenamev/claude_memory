# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::SessionId do
  describe "#initialize" do
    it "accepts a string value" do
      session_id = described_class.new("abc-123")
      expect(session_id.value).to eq("abc-123")
    end

    it "converts non-string values to strings" do
      session_id = described_class.new(12345)
      expect(session_id.value).to eq("12345")
    end

    it "raises error for empty string" do
      expect { described_class.new("") }.to raise_error(ArgumentError, "Session ID cannot be empty")
    end

    it "raises error for nil" do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, "Session ID cannot be empty")
    end

    it "freezes the object" do
      session_id = described_class.new("test")
      expect(session_id).to be_frozen
    end
  end

  describe "#to_s" do
    it "returns the string value" do
      session_id = described_class.new("my-session")
      expect(session_id.to_s).to eq("my-session")
    end
  end

  describe "#==" do
    it "returns true for same value" do
      session_id1 = described_class.new("test")
      session_id2 = described_class.new("test")
      expect(session_id1).to eq(session_id2)
    end

    it "returns false for different values" do
      session_id1 = described_class.new("test1")
      session_id2 = described_class.new("test2")
      expect(session_id1).not_to eq(session_id2)
    end

    it "returns false for different types" do
      session_id = described_class.new("test")
      expect(session_id).not_to eq("test")
    end
  end

  describe "#eql?" do
    it "behaves like ==" do
      session_id1 = described_class.new("test")
      session_id2 = described_class.new("test")
      expect(session_id1.eql?(session_id2)).to be true
    end
  end

  describe "#hash" do
    it "returns same hash for equal values" do
      session_id1 = described_class.new("test")
      session_id2 = described_class.new("test")
      expect(session_id1.hash).to eq(session_id2.hash)
    end

    it "can be used as hash key" do
      session_id1 = described_class.new("test")
      session_id2 = described_class.new("test")
      hash = {session_id1 => "value"}
      expect(hash[session_id2]).to eq("value")
    end
  end
end
