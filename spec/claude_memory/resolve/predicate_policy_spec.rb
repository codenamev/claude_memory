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
    it "returns the curated predicate vocabulary" do
      expect(described_class.known_predicates).to contain_exactly(
        "convention",
        "decision",
        "architecture",
        "uses_framework",
        "uses_language",
        "uses_database",
        "deployment_platform",
        "auth_method"
      )
    end
  end

  describe ".single?" do
    it "returns true for single-cardinality predicates" do
      expect(described_class.single?("uses_database")).to be true
      expect(described_class.single?("auth_method")).to be true
      expect(described_class.single?("deployment_platform")).to be true
    end

    it "returns false for multi-cardinality predicates" do
      expect(described_class.single?("convention")).to be false
      expect(described_class.single?("decision")).to be false
      expect(described_class.single?("architecture")).to be false
      expect(described_class.single?("uses_framework")).to be false
      expect(described_class.single?("uses_language")).to be false
    end

    it "treats uses_framework as multi-cardinality" do
      # Regression: prior single-value classification silently superseded
      # legitimate facts across several project DBs.
      expect(described_class.single?("uses_framework")).to be false
    end

    it "treats pruned predicates as unknown (default multi)" do
      # These were removed from the policy after zero usage across all
      # observed project DBs. Unknown predicates fall through to the
      # default multi-value policy.
      %w[preference workflow dependency testing_strategy tool_usage
        ci_platform primary_language].each do |pruned|
        expect(described_class.single?(pruned)).to be false
      end
    end
  end

  describe ".exclusive?" do
    it "returns true for exclusive predicates" do
      expect(described_class.exclusive?("deployment_platform")).to be true
      expect(described_class.exclusive?("uses_database")).to be true
      expect(described_class.exclusive?("auth_method")).to be true
    end

    it "returns false for non-exclusive predicates" do
      expect(described_class.exclusive?("convention")).to be false
      expect(described_class.exclusive?("architecture")).to be false
      expect(described_class.exclusive?("uses_framework")).to be false
      expect(described_class.exclusive?("uses_language")).to be false
    end
  end
end
