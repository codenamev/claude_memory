# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::NullFact do
  subject(:null_fact) { described_class.new }

  describe "#present?" do
    it "returns false" do
      expect(null_fact.present?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash with nil values" do
      result = null_fact.to_h
      expect(result).to be_a(Hash)
      expect(result[:id]).to be_nil
      expect(result[:subject_name]).to be_nil
      expect(result[:predicate]).to be_nil
      expect(result[:object_literal]).to be_nil
      expect(result[:status]).to eq("not_found")
      expect(result[:confidence]).to eq(0.0)
      expect(result[:valid_from]).to be_nil
      expect(result[:valid_to]).to be_nil
    end
  end

  describe "attribute accessors" do
    it "returns nil for id" do
      expect(null_fact[:id]).to be_nil
    end

    it "returns nil for subject_name" do
      expect(null_fact[:subject_name]).to be_nil
    end

    it "returns nil for predicate" do
      expect(null_fact[:predicate]).to be_nil
    end

    it "returns nil for object_literal" do
      expect(null_fact[:object_literal]).to be_nil
    end

    it "returns 'not_found' for status" do
      expect(null_fact[:status]).to eq("not_found")
    end

    it "returns 0.0 for confidence" do
      expect(null_fact[:confidence]).to eq(0.0)
    end
  end
end
