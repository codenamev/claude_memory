# frozen_string_literal: true

RSpec.describe ClaudeMemory::Resolve::PredicatePolicy do
  describe ".policy_for" do
    it "returns policy for known predicates" do
      policy = described_class.policy_for("uses_database")
      expect(policy).to eq({cardinality: :single, exclusive: true})
    end

    it "returns default policy for unknown predicates" do
      policy = described_class.policy_for("custom_predicate")
      expect(policy).to eq({cardinality: :multi, exclusive: false})
    end
  end

  describe ".single?" do
    it "returns true for single-cardinality predicates" do
      expect(described_class.single?("uses_database")).to be true
      expect(described_class.single?("auth_method")).to be true
    end

    it "returns false for multi-cardinality predicates" do
      expect(described_class.single?("convention")).to be false
      expect(described_class.single?("decision")).to be false
    end
  end

  describe ".exclusive?" do
    it "returns true for exclusive predicates" do
      expect(described_class.exclusive?("deployment_platform")).to be true
    end

    it "returns false for non-exclusive predicates" do
      expect(described_class.exclusive?("convention")).to be false
    end
  end
end
