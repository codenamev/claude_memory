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

  describe ".known_predicates" do
    it "returns all known predicate names" do
      predicates = described_class.known_predicates
      expect(predicates).to include("convention", "decision", "uses_database",
        "preference", "workflow", "primary_language")
      expect(predicates.size).to eq(13)
    end
  end

  describe ".single?" do
    it "returns true for single-cardinality predicates" do
      expect(described_class.single?("uses_database")).to be true
      expect(described_class.single?("auth_method")).to be true
      expect(described_class.single?("primary_language")).to be true
      expect(described_class.single?("ci_platform")).to be true
    end

    it "returns false for multi-cardinality predicates" do
      expect(described_class.single?("convention")).to be false
      expect(described_class.single?("decision")).to be false
      expect(described_class.single?("preference")).to be false
      expect(described_class.single?("workflow")).to be false
      expect(described_class.single?("dependency")).to be false
      expect(described_class.single?("testing_strategy")).to be false
      expect(described_class.single?("tool_usage")).to be false
    end

    it "treats uses_framework as multi-cardinality" do
      # Real projects use multiple frameworks (Rails + Turbo + Tailwind).
      # Regression: prior single-value classification silently superseded
      # legitimate facts across several project DBs.
      expect(described_class.single?("uses_framework")).to be false
    end
  end

  describe ".exclusive?" do
    it "returns true for exclusive predicates" do
      expect(described_class.exclusive?("deployment_platform")).to be true
      expect(described_class.exclusive?("primary_language")).to be true
      expect(described_class.exclusive?("ci_platform")).to be true
    end

    it "returns false for non-exclusive predicates" do
      expect(described_class.exclusive?("convention")).to be false
      expect(described_class.exclusive?("preference")).to be false
      expect(described_class.exclusive?("workflow")).to be false
      expect(described_class.exclusive?("uses_framework")).to be false
    end
  end
end
