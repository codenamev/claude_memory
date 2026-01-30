# frozen_string_literal: true

require_relative "support/eval_helpers"

# Week 2: Refactored to use extracted helpers
# This eval tests whether memory improves responses about project conventions

RSpec.describe "Convention Recall Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_facts([
      {
        predicate: "convention",
        object: "Use 2-space indentation for Ruby files",
        text: "Use 2-space indentation for Ruby files",
        fts_keywords: "coding convention style"
      },
      {
        predicate: "convention",
        object: "Prefer RSpec's expect syntax over should syntax",
        text: "Prefer RSpec's expect syntax over should syntax",
        fts_keywords: "convention style pattern"
      }
    ])

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response(
      "Based on the project memory, this Ruby project follows these conventions:\n\n" \
      "1. Use 2-space indentation for Ruby files\n" \
      "2. Prefer RSpec's expect syntax over should syntax\n\n" \
      "These conventions ensure consistent code style across the project.",
      session_id: "stub-session-convention-memory"
    )
  end

  def stub_claude_response_without_memory
    stub_success_response(
      "For Ruby projects, common conventions include:\n\n" \
      "- Follow the Ruby Style Guide\n" \
      "- Use descriptive variable names\n" \
      "- Keep methods short and focused\n\n" \
      "I don't have specific information about this project's conventions.",
      session_id: "stub-session-convention-baseline"
    )
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "mentions stored conventions when asked" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_indentation = includes_any?(response, "2-space", "2 space")
      mentions_rspec = includes_any?(response, "expect syntax", "expect")

      expect(mentions_indentation).to be(true), "Response should mention 2-space indentation"
      expect(mentions_rspec).to be(true), "Response should mention expect syntax"
    end

    it "calculates behavioral score" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_indentation = includes_any?(response, "2-space", "2 space")
      mentions_rspec = includes_any?(response, "expect syntax", "expect")

      score = score_from_checks(mentions_indentation, mentions_rspec)

      expect(score).to eq(1.0)
    end
  end

  context "baseline (no memory)" do
    it "does not mention specific project conventions" do
      result = stub_claude_response_without_memory
      response = result[:result]

      mentions_project_specific = includes_any?(response, "2-space", "expect syntax")

      expect(mentions_project_specific).to be(false),
        "Baseline should not mention project-specific conventions without memory"
    end

    it "has lower behavioral score than memory-enabled" do
      result = stub_claude_response_without_memory
      response = result[:result]

      mentions_indentation = includes_any?(response, "2-space", "2 space")
      mentions_rspec = includes_any?(response, "expect syntax", "expect")

      score = score_from_checks(mentions_indentation, mentions_rspec)

      expect(score).to eq(0.0), "Baseline should not include stored conventions"
    end
  end

  describe "fixture setup" do
    it "creates memory database with conventions" do
      populate_fixture_memory

      expect(File.exist?(db_path)).to be true

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.all

      expect(facts.size).to eq(2)
      expect(facts.map { |f| f[:predicate] }).to all(eq("convention"))

      store.close
    end
  end
end
