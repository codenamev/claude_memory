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
        "reference",
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

  describe ".canonicalize" do
    before do
      ClaudeMemory::Deprecations.reset!
      ENV[ClaudeMemory::Deprecations::ENV_OPT_OUT] = "1"
    end
    after { ENV.delete(ClaudeMemory::Deprecations::ENV_OPT_OUT) }

    it "rewrites known synonyms to the canonical form" do
      expect(described_class.canonicalize("has_convention")).to eq("convention")
      expect(described_class.canonicalize("primary_language")).to eq("uses_language")
    end

    it "leaves unknown and already-canonical predicates alone" do
      expect(described_class.canonicalize("convention")).to eq("convention")
      expect(described_class.canonicalize("something_novel")).to eq("something_novel")
    end

    it "handles nil safely" do
      expect(described_class.canonicalize(nil)).to be_nil
    end

    it "emits a deprecation warning when a synonym is canonicalized" do
      ENV.delete(ClaudeMemory::Deprecations::ENV_OPT_OUT)
      output = StringIO.new
      allow($stderr).to receive(:puts) { |msg| output.puts(msg) }

      described_class.canonicalize("has_convention")

      expect(output.string).to include("DEPRECATION")
      expect(output.string).to include("predicate=has_convention")
      expect(output.string).to include("predicate=convention")
      expect(output.string).to include("1.0.0")
    end

    it "does NOT emit a deprecation when the canonical form is passed" do
      ENV.delete(ClaudeMemory::Deprecations::ENV_OPT_OUT)
      output = StringIO.new
      allow($stderr).to receive(:puts) { |msg| output.puts(msg) }

      described_class.canonicalize("convention")

      expect(output.string).to be_empty
    end
  end

  describe ".section_for" do
    it "maps canonical predicates to their snapshot sections" do
      expect(described_class.section_for("decision")).to eq(:decisions)
      expect(described_class.section_for("convention")).to eq(:conventions)
      expect(described_class.section_for("uses_database")).to eq(:constraints)
      expect(described_class.section_for("uses_framework")).to eq(:constraints)
      expect(described_class.section_for("uses_language")).to eq(:constraints)
      expect(described_class.section_for("deployment_platform")).to eq(:constraints)
      expect(described_class.section_for("auth_method")).to eq(:constraints)
    end

    it "honors legacy prefix and suffix patterns" do
      expect(described_class.section_for("decided_pattern")).to eq(:decisions)
      expect(described_class.section_for("naming_convention")).to eq(:conventions)
    end

    it "routes unknown and unmapped predicates to :additional" do
      expect(described_class.section_for("architecture")).to eq(:additional)
      expect(described_class.section_for("something_novel")).to eq(:additional)
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
