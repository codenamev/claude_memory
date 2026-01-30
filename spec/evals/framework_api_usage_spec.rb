# frozen_string_literal: true

require_relative "support/eval_helpers"

# Tests whether memory helps use correct framework APIs
# This eval verifies that memory prevents suggesting wrong frameworks
# and promotes correct API usage patterns

RSpec.describe "Framework API Usage Eval", :eval do
  include EvalHelpers::SharedSetup
  include EvalHelpers::ResponseStubs
  include EvalHelpers::ScoringHelpers

  def populate_fixture_memory
    builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)

    builder.add_facts([
      {
        predicate: "uses_framework",
        object: "Sequel",
        text: "This project uses Sequel for database access, not ActiveRecord",
        fts_keywords: "database orm framework"
      },
      {
        predicate: "convention",
        object: "Use Sequel datasets, avoid raw SQL",
        text: "Prefer Sequel dataset methods over raw SQL queries",
        fts_keywords: "database query pattern"
      },
      {
        predicate: "convention",
        object: "Wrap database writes in transactions",
        text: "All database writes should be wrapped in db.transaction blocks",
        fts_keywords: "database safety transaction"
      }
    ])

    builder.close
  end

  def stub_claude_response_with_memory
    stub_success_response(
      "Since this project uses Sequel, here's the correct approach:\n\n" \
      "```ruby\n" \
      "db.transaction do\n" \
      "  users = db[:users].where(active: true)\n" \
      "  users.update(status: 'verified')\n" \
      "end\n" \
      "```\n\n" \
      "Key points:\n" \
      "- Uses Sequel dataset methods (not raw SQL)\n" \
      "- Wraps writes in transaction for safety\n" \
      "- Follows project's database conventions",
      session_id: "stub-session-framework-memory"
    )
  end

  def stub_claude_response_without_memory
    stub_success_response(
      "For Ruby database access, you could use:\n\n" \
      "```ruby\n" \
      "# With ActiveRecord\n" \
      "User.where(active: true).update_all(status: 'verified')\n\n" \
      "# Or with raw SQL\n" \
      "ActiveRecord::Base.connection.execute(\n" \
      "  \"UPDATE users SET status = 'verified' WHERE active = true\"\n" \
      ")\n" \
      "```\n\n" \
      "Choose based on your ORM.",
      session_id: "stub-session-framework-baseline"
    )
  end

  describe "with memory populated" do
    before do
      populate_fixture_memory
    end

    it "uses correct framework API" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_sequel = includes_any?(response, "Sequel", "db[:users]")
      avoids_activerecord = !includes_any?(response, "ActiveRecord")
      uses_datasets = includes_any?(response, "dataset", "db[:", "where")
      uses_transactions = includes_any?(response, "transaction")

      expect(mentions_sequel).to be(true), "Response should mention Sequel"
      expect(avoids_activerecord).to be(true), "Response should not suggest ActiveRecord"
      expect(uses_datasets).to be(true), "Response should use dataset methods"
      expect(uses_transactions).to be(true), "Response should mention transactions"
    end

    it "calculates behavioral score for framework adherence" do
      result = stub_claude_response_with_memory
      response = result[:result]

      mentions_sequel = includes_any?(response, "Sequel")
      uses_datasets = includes_any?(response, "dataset", "db[:")
      uses_transactions = includes_any?(response, "transaction")

      score = score_from_checks(
        mentions_sequel,
        uses_datasets,
        uses_transactions
      )

      expect(score).to eq(1.0)
    end
  end

  context "baseline (no memory)" do
    it "suggests wrong framework without memory" do
      result = stub_claude_response_without_memory
      response = result[:result]

      suggests_activerecord = includes_any?(response, "ActiveRecord")
      uses_raw_sql = includes_any?(response, "execute", "raw SQL")

      expect(suggests_activerecord).to be(true), "Baseline suggests ActiveRecord"
      expect(uses_raw_sql).to be(true), "Baseline suggests raw SQL"
    end

    it "has lower framework adherence score" do
      result = stub_claude_response_without_memory
      response = result[:result]

      mentions_sequel = includes_any?(response, "Sequel")
      uses_datasets = includes_any?(response, "db[:") && !includes_any?(response, "ActiveRecord")
      uses_transactions = includes_any?(response, "db.transaction")

      score = score_from_checks(
        mentions_sequel,
        uses_datasets,
        uses_transactions
      )

      expect(score).to eq(0.0), "Baseline should not know to use Sequel"
    end
  end

  describe "fixture setup" do
    it "creates memory database with framework facts" do
      populate_fixture_memory

      expect(File.exist?(db_path)).to be true

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.all

      expect(facts.size).to eq(3)
      expect(facts.any? { |f| f[:predicate] == "uses_framework" }).to be true
      expect(facts.any? { |f| f[:object_literal].include?("Sequel") }).to be true

      store.close
    end
  end
end
