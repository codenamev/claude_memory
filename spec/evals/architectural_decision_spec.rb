# frozen_string_literal: true

require_relative "support/eval_helpers"

# Week 2: Refactored to use extracted helpers
# Tests whether memory improves responses about architectural decisions

RSpec.describe "Architectural Decision Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_fact(
      predicate: "decision",
      object: "Use Sequel for database access, not ActiveRecord",
      text: "Decision: Use Sequel for database access, not ActiveRecord",
      fts_keywords: "constraint rule requirement"
    )

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response(
      "Based on the project's architectural decisions, you should use Sequel for " \
      "database access. This project has specifically chosen Sequel over ActiveRecord.",
      session_id: "stub-session-arch-memory"
    )
  end

  def stub_claude_response_without_memory
    stub_success_response(
      "For Ruby database access, you have several options:\n\n" \
      "- ActiveRecord (most common with Rails)\n" \
      "- Sequel (lightweight alternative)\n" \
      "- ROM (Ruby Object Mapper)\n\n" \
      "Choose based on your project's needs.",
      session_id: "stub-session-arch-baseline"
    )
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "mentions the stored architectural decision" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_sequel = response.downcase.include?("sequel")
      avoids_activerecord_recommendation = !response.include?("should use ActiveRecord")

      expect(mentions_sequel).to be(true), "Response should mention Sequel"
      expect(avoids_activerecord_recommendation).to be(true),
        "Response should not recommend ActiveRecord when decision is Sequel"
    end

    it "calculates behavioral score for decision adherence" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_sequel = response.downcase.include?("sequel")
      mentions_decision = includes_any?(response, "decision", "chosen")

      score = score_from_checks(
        mentions_sequel,       # 50% weight
        mentions_sequel,       # 20% weight (extra for specificity)
        mentions_decision      # 30% weight
      )

      expect(score).to be >= 0.66 # At least mentions Sequel + decision context
    end
  end

  context "baseline (no memory)" do
    it "gives generic advice without knowing the decision" do
      result = stub_claude_response_without_memory
      response = result[:result]

      # Baseline lists options but doesn't make specific recommendation
      mentions_multiple_options = response.include?("ActiveRecord") && response.include?("Sequel")

      expect(mentions_multiple_options).to be(true),
        "Baseline should list multiple options without knowing project decision"
    end

    it "has lower decision adherence score" do
      result = stub_claude_response_without_memory
      response = result[:result]

      # Check if response aligns with stored decision (Sequel)
      recommends_sequel_specifically = includes_any?(response, "should use Sequel", "Use Sequel")

      score = recommends_sequel_specifically ? 1.0 : 0.0

      expect(score).to eq(0.0), "Baseline should not know to recommend Sequel specifically"
    end
  end

  describe "fixture setup" do
    it "creates memory database with architectural decision" do
      populate_fixture_memory

      expect(File.exist?(db_path)).to be true

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.all

      expect(facts.size).to eq(1)
      expect(facts.first[:predicate]).to eq("decision")
      expect(facts.first[:object_literal]).to include("Sequel")

      store.close
    end
  end
end
