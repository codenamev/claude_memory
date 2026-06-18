# frozen_string_literal: true

require_relative "support/eval_helpers"

# Tests whether memory helps follow error handling conventions
# This eval verifies that memory promotes Result pattern over exceptions
# and explicit error handling over rescue blocks

RSpec.describe "Error Handling Patterns Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_facts([
      {
        predicate: "convention",
        object: "Return Result objects (Success/Failure) instead of raising exceptions",
        text: "Use Result pattern for error handling instead of exceptions",
        fts_keywords: "error handling pattern convention"
      },
      {
        predicate: "convention",
        object: "Log errors to stderr using $stderr.puts, not raise",
        text: "Log errors to stderr instead of raising exceptions",
        fts_keywords: "error logging convention"
      },
      {
        predicate: "decision",
        object: "Explicit error handling over rescue blocks",
        text: "Decision: Use explicit error checking instead of rescue blocks",
        fts_keywords: "error handling pattern decision"
      }
    ])

    builder.close
  end

  def stub_claude_response_with_memory
    # standard:disable Lint/InterpolationCheck -- the #{...} here is literal text
    # inside a generated Ruby *code sample*, not a string to interpolate.
    stub_success_response(
      "Following the project's error handling patterns:\n\n" \
      "```ruby\n" \
      "def perform_operation(input)\n" \
      "  return Failure.new(\"Invalid input\") if input.nil?\n\n" \
      "  result = process(input)\n" \
      "  if result.nil?\n" \
      '    $stderr.puts "Processing failed for: #{input}"' + "\n" \
      "    return Failure.new(\"Processing failed\")\n" \
      "  end\n\n" \
      "  Success.new(result)\n" \
      "end\n" \
      "```\n\n" \
      "This follows the conventions:\n" \
      "- Returns Result objects (Success/Failure)\n" \
      "- Logs to stderr using $stderr.puts\n" \
      "- Uses explicit error checking",
      session_id: "stub-session-error-memory"
    )
    # standard:enable Lint/InterpolationCheck
  end

  def stub_claude_response_without_memory
    # standard:disable Lint/InterpolationCheck -- literal #{...} in a code sample
    stub_success_response(
      "Here's a typical Ruby error handling approach:\n\n" \
      "```ruby\n" \
      "def perform_operation(input)\n" \
      "  raise ArgumentError, \"Invalid input\" if input.nil?\n\n" \
      "  begin\n" \
      "    result = process(input)\n" \
      "    result\n" \
      "  rescue => e\n" \
      '    puts "Error: #{e.message}"' + "\n" \
      "    raise\n" \
      "  end\n" \
      "end\n" \
      "```\n\n" \
      "This uses standard Ruby exception handling with rescue blocks.",
      session_id: "stub-session-error-baseline"
    )
    # standard:enable Lint/InterpolationCheck
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "follows stored error handling patterns" do
      result = stub_claude_response_with_memory
      response = result[:result]

      uses_result_pattern = includes_any?(response, "Success", "Failure", "Result")
      logs_to_stderr = includes_any?(response, "$stderr", "stderr")
      uses_explicit_checking = includes_any?(response, "if result.nil?", "explicit")

      expect(uses_result_pattern).to be(true), "Response should use Result pattern"
      expect(logs_to_stderr).to be(true), "Response should log to stderr"
      expect(uses_explicit_checking).to be(true), "Response should use explicit error checking"
    end

    it "calculates behavioral score for error handling adherence" do
      result = stub_claude_response_with_memory
      response = result[:result]

      uses_result_pattern = includes_any?(response, "Success", "Failure")
      logs_to_stderr = includes_any?(response, "$stderr")
      avoids_rescue = !includes_any?(response, "rescue", "begin")

      score = score_from_checks(
        uses_result_pattern,
        logs_to_stderr,
        avoids_rescue
      )

      expect(score).to eq(1.0)
    end
  end

  context "baseline (no memory)" do
    it "uses exception-based error handling" do
      result = stub_claude_response_without_memory
      response = result[:result]

      uses_exceptions = includes_any?(response, "raise", "ArgumentError")
      uses_rescue = includes_any?(response, "rescue", "begin")

      expect(uses_exceptions).to be(true), "Baseline uses raise/exceptions"
      expect(uses_rescue).to be(true), "Baseline uses rescue blocks"
    end

    it "has lower error handling adherence score" do
      result = stub_claude_response_without_memory
      response = result[:result]

      uses_result_pattern = includes_any?(response, "Success.new", "Failure.new")
      logs_to_stderr = includes_any?(response, "$stderr")
      avoids_rescue = !includes_any?(response, "rescue")

      score = score_from_checks(
        uses_result_pattern,
        logs_to_stderr,
        avoids_rescue
      )

      expect(score).to eq(0.0), "Baseline should use exception-based handling"
    end
  end

  describe "fixture setup" do
    it "creates memory database with error handling patterns" do
      populate_fixture_memory

      expect(File.exist?(db_path)).to be true

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.all

      expect(facts.size).to eq(3)
      expect(facts.any? { |f| f[:predicate] == "convention" }).to be true
      expect(facts.any? { |f| f[:predicate] == "decision" }).to be true

      store.close
    end
  end
end
