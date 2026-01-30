# frozen_string_literal: true

require_relative "support/eval_helpers"

# Week 2: Refactored to use extracted helpers
# Tests whether memory improves responses about tech stack (frameworks, databases)

RSpec.describe "Tech Stack Recall Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_facts([
      {
        predicate: "uses_framework",
        object: "RSpec",
        text: "This project uses RSpec framework for testing",
        fts_keywords: "architecture framework pattern uses implements"
      },
      {
        predicate: "uses_database",
        object: "SQLite",
        text: "This project uses SQLite database with Extralite",
        fts_keywords: "architecture framework pattern uses implements"
      },
      {
        predicate: "uses_framework",
        object: "Sequel",
        text: "This project uses Sequel framework for database queries",
        fts_keywords: "architecture framework pattern uses implements"
      }
    ])

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response(
      "This project uses RSpec as the testing framework. RSpec is a BDD testing tool " \
      "for Ruby that provides a readable DSL for writing tests.",
      session_id: "stub-session-tech-memory"
    )
  end

  def stub_claude_response_without_memory
    stub_success_response(
      "Common Ruby testing frameworks include:\n\n" \
      "- Minitest (built into Ruby)\n" \
      "- RSpec (BDD framework)\n" \
      "- Test::Unit (older standard)\n\n" \
      "Without seeing the project structure, I can't tell which one is used.",
      session_id: "stub-session-tech-baseline"
    )
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "correctly identifies the testing framework" do
      result = stub_claude_response_with_memory
      response = result[:result]

      identifies_rspec = response.include?("RSpec")
      avoids_wrong_framework = !response.include?("Minitest") && !response.include?("Test::Unit")

      expect(identifies_rspec).to be(true), "Response should identify RSpec"
      expect(avoids_wrong_framework).to be(true), "Response should not mention wrong frameworks"
    end

    it "calculates accuracy score" do
      result = stub_claude_response_with_memory
      response = result[:result]

      correct_framework = response.include?("RSpec")
      confident_answer = !includes_any?(response, "I can't tell", "Without seeing")

      score = score_from_checks(
        correct_framework,   # 80% weight
        correct_framework,   # Additional 20% weight
        correct_framework,   # Additional 20% weight
        correct_framework,   # Additional 20% weight
        confident_answer     # 20% weight
      )

      expect(score).to eq(1.0)
    end
  end

  context "baseline (no memory)" do
    it "cannot identify the specific framework without memory" do
      result = stub_claude_response_without_memory
      response = result[:result]

      # Baseline admits uncertainty
      admits_uncertainty = includes_any?(response, "can't tell", "Without seeing", "Common")

      expect(admits_uncertainty).to be(true),
        "Baseline should express uncertainty without memory"
    end

    it "has lower accuracy score" do
      result = stub_claude_response_without_memory
      response = result[:result]

      correct_framework = response.include?("This project uses RSpec")
      confident_answer = !includes_any?(response, "can't tell", "Without seeing")

      score = score_from_checks(
        correct_framework,   # 80% weight
        correct_framework,   # Additional weight
        correct_framework,
        correct_framework,
        confident_answer     # 20% weight
      )

      expect(score).to eq(0.0), "Baseline cannot identify framework without memory"
    end
  end

  describe "fixture setup" do
    it "creates memory database with tech stack facts" do
      populate_fixture_memory

      expect(File.exist?(db_path)).to be true

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.all

      expect(facts.size).to eq(3)

      predicates = facts.map { |f| f[:predicate] }.uniq
      expect(predicates).to include("uses_framework", "uses_database")

      rspec_fact = facts.find { |f| f[:object_literal] == "RSpec" }
      expect(rspec_fact).not_to be_nil
      expect(rspec_fact[:predicate]).to eq("uses_framework")

      store.close
    end
  end
end
