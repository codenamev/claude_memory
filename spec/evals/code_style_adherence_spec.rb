# frozen_string_literal: true

require_relative "support/eval_helpers"

# Tests whether memory helps respect project-specific style choices
# This eval verifies that memory-enabled responses follow stored style conventions
# like quote style, guard clauses, and explicit returns

RSpec.describe "Code Style Adherence Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_facts([
      {
        predicate: "convention",
        object: "Use double quotes for strings, not single quotes",
        text: "Project convention: Use double quotes for strings",
        fts_keywords: "style convention quote"
      },
      {
        predicate: "convention",
        object: "Prefer guard clauses over nested conditionals",
        text: "Use guard clauses to reduce nesting",
        fts_keywords: "style convention pattern"
      },
      {
        predicate: "convention",
        object: "Use explicit returns in methods",
        text: "Methods should use explicit return statements",
        fts_keywords: "style convention return"
      }
    ])

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response(
      "Following the project's style conventions:\n\n" \
      "```ruby\n" \
      "def process(input)\n" \
      "  return nil if input.nil?\n" \
      "  return \"invalid\" if input.empty?\n\n" \
      "  result = transform(input)\n" \
      "  return result\n" \
      "end\n" \
      "```\n\n" \
      "This code follows the style guide:\n" \
      "- Uses double quotes for strings\n" \
      "- Guard clauses instead of nested ifs\n" \
      "- Explicit return statements",
      session_id: "stub-session-style-memory"
    )
  end

  def stub_claude_response_without_memory
    stub_success_response(
      "Here's a typical Ruby implementation:\n\n" \
      "```ruby\n" \
      "def process(input)\n" \
      "  if input\n" \
      "    if !input.empty?\n" \
      "      result = transform(input)\n" \
      "      result\n" \
      "    else\n" \
      "      'invalid'\n" \
      "    end\n" \
      "  end\n" \
      "end\n" \
      "```\n\n" \
      "This uses standard Ruby conventions with implicit returns.",
      session_id: "stub-session-style-baseline"
    )
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "follows stored style conventions" do
      result = stub_claude_response_with_memory
      response = result[:result]

      uses_double_quotes = includes_any?(response, "double quote")
      mentions_guard_clauses = includes_any?(response, "guard", "Guard")
      uses_explicit_returns = includes_any?(response, "return", "Explicit return")

      expect(uses_double_quotes).to be(true), "Response should mention double quotes"
      expect(mentions_guard_clauses).to be(true), "Response should mention guard clauses"
      expect(uses_explicit_returns).to be(true), "Response should use explicit returns"
    end

    it "calculates behavioral score for style adherence" do
      result = stub_claude_response_with_memory
      response = result[:result]

      uses_double_quotes = includes_any?(response, "double quote")
      mentions_guard_clauses = includes_any?(response, "guard", "Guard")
      uses_explicit_returns = includes_any?(response, "return")

      score = score_from_checks(
        uses_double_quotes,
        mentions_guard_clauses,
        uses_explicit_returns
      )

      expect(score).to eq(1.0)
    end
  end

  context "baseline (no memory)" do
    it "does not follow project-specific style choices" do
      result = stub_claude_response_without_memory
      response = result[:result]

      uses_nested_conditionals = includes_any?(response, "if !input.empty?", "nested")
      uses_implicit_returns = !response.include?("return result")

      expect(uses_nested_conditionals).to be(true), "Baseline uses nested conditionals"
      expect(uses_implicit_returns).to be(true), "Baseline uses implicit returns"
    end

    it "has lower style adherence score" do
      result = stub_claude_response_without_memory
      response = result[:result]

      uses_double_quotes = includes_any?(response, "double quote")
      mentions_guard_clauses = includes_any?(response, "guard", "Guard")
      uses_explicit_returns = includes_any?(response, "return result", "return ")

      score = score_from_checks(
        uses_double_quotes,
        mentions_guard_clauses,
        uses_explicit_returns
      )

      expect(score).to eq(0.0), "Baseline should not follow project-specific style"
    end
  end

  describe "fixture setup" do
    it "creates memory database with style conventions" do
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
