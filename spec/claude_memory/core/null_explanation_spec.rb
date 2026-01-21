# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::NullExplanation do
  subject(:null_explanation) { described_class.new }

  describe "#present?" do
    it "returns false" do
      expect(null_explanation.present?).to be false
    end
  end

  describe "#fact" do
    it "returns a NullFact" do
      expect(null_explanation.fact).to be_a(ClaudeMemory::Core::NullFact)
    end
  end

  describe "#receipts" do
    it "returns empty array" do
      expect(null_explanation.receipts).to eq([])
    end
  end

  describe "#superseded_by" do
    it "returns empty array" do
      expect(null_explanation.superseded_by).to eq([])
    end
  end

  describe "#supersedes" do
    it "returns empty array" do
      expect(null_explanation.supersedes).to eq([])
    end
  end

  describe "#conflicts" do
    it "returns empty array" do
      expect(null_explanation.conflicts).to eq([])
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      result = null_explanation.to_h
      expect(result).to be_a(Hash)
      expect(result[:fact]).to be_a(Hash)
      expect(result[:fact][:status]).to eq("not_found")
      expect(result[:receipts]).to eq([])
      expect(result[:superseded_by]).to eq([])
      expect(result[:supersedes]).to eq([])
      expect(result[:conflicts]).to eq([])
    end
  end

  describe "hash accessor" do
    it "supports hash-like access" do
      expect(null_explanation[:fact]).to be_a(Hash)
      expect(null_explanation[:receipts]).to eq([])
    end
  end
end
