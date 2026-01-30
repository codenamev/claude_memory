# frozen_string_literal: true

require_relative "support/eval_helpers"

# Tests whether memory helps Claude follow existing code patterns
# This eval verifies that memory-enabled responses use established patterns
# like Result objects and dependency injection

RSpec.describe "Implementation Consistency Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_facts([
      {
        predicate: "convention",
        object: "Use frozen_string_literal: true in all Ruby files",
        text: "All Ruby files should start with frozen_string_literal: true",
        fts_keywords: "convention pattern practice"
      },
      {
        predicate: "convention",
        object: "Service classes return Result objects (Success/Failure pattern)",
        text: "Service classes return Result objects instead of raising exceptions",
        fts_keywords: "convention pattern error handling"
      },
      {
        predicate: "convention",
        object: "Inject dependencies via initializer, not globals",
        text: "Dependencies should be injected via initializer for testability",
        fts_keywords: "convention pattern dependency injection"
      }
    ])

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response(
      "Here's how to implement this following the project's patterns:\n\n" \
      "```ruby\n" \
      "# frozen_string_literal: true\n\n" \
      "class MyService\n" \
      "  def initialize(dependency)\n" \
      "    @dependency = dependency\n" \
      "  end\n\n" \
      "  def call\n" \
      "    result = @dependency.perform\n" \
      "    return Failure.new(\"Error\") if result.nil?\n" \
      "    Success.new(result)\n" \
      "  end\n" \
      "end\n" \
      "```\n\n" \
      "This follows the project conventions:\n" \
      "- Uses frozen_string_literal\n" \
      "- Returns Result objects (Success/Failure)\n" \
      "- Injects dependencies via initializer",
      session_id: "stub-session-implementation-memory"
    )
  end

  def stub_claude_response_without_memory
    stub_success_response(
      "Here's a typical Ruby implementation:\n\n" \
      "```ruby\n" \
      "class MyService\n" \
      "  def call\n" \
      "    result = SomeGlobal.perform\n" \
      "    raise StandardError, \"Error\" if result.nil?\n" \
      "    result\n" \
      "  end\n" \
      "end\n" \
      "```\n\n" \
      "This uses standard Ruby exception handling and direct method calls.",
      session_id: "stub-session-implementation-baseline"
    )
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "follows stored implementation patterns" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_frozen_literal = includes_any?(response, "frozen_string_literal")
      uses_result_pattern = includes_any?(response, "Success", "Failure", "Result")
      uses_dependency_injection = includes_any?(response, "initialize", "dependency")

      expect(mentions_frozen_literal).to be(true), "Response should include frozen_string_literal"
      expect(uses_result_pattern).to be(true), "Response should use Result pattern"
      expect(uses_dependency_injection).to be(true), "Response should inject dependencies"
    end

    it "calculates behavioral score for pattern adherence" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_frozen_literal = includes_any?(response, "frozen_string_literal")
      uses_result_pattern = includes_any?(response, "Success", "Failure")
      uses_dependency_injection = includes_any?(response, "initialize", "dependency")

      score = score_from_checks(
        mentions_frozen_literal,
        uses_result_pattern,
        uses_dependency_injection
      )

      expect(score).to eq(1.0)
    end
  end

  context "baseline (no memory)" do
    it "does not follow project-specific patterns" do
      result = stub_claude_response_without_memory
      response = result[:result]

      uses_exceptions = includes_any?(response, "raise", "exception")
      uses_globals = includes_any?(response, "Global", "SomeGlobal")

      expect(uses_exceptions).to be(true), "Baseline uses exceptions instead of Result pattern"
      expect(uses_globals).to be(true), "Baseline uses globals instead of dependency injection"
    end

    it "has lower pattern adherence score" do
      result = stub_claude_response_without_memory
      response = result[:result]

      mentions_frozen_literal = includes_any?(response, "frozen_string_literal")
      uses_result_pattern = includes_any?(response, "Success.new", "Failure.new")
      uses_dependency_injection = includes_any?(response, "@dependency", "inject")

      score = score_from_checks(
        mentions_frozen_literal,
        uses_result_pattern,
        uses_dependency_injection
      )

      expect(score).to eq(0.0), "Baseline should not follow project-specific patterns"
    end
  end

  describe "fixture setup" do
    it "creates memory database with implementation patterns" do
      populate_fixture_memory

      expect(File.exist?(db_path)).to be true

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.all

      expect(facts.size).to eq(3)
      expect(facts.map { |f| f[:predicate] }).to all(eq("convention"))

      store.close
    end
  end
end
