# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe "Recall intent parameter" do
  let(:db_path) { File.join(Dir.tmpdir, "recall_intent_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:fts) { ClaudeMemory::Index::LexicalFTS.new(store) }
  let(:recall) { ClaudeMemory::Recall.new(store, fts: fts) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_content_with_fact(text, predicate, object)
    content_id = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      raw_text: text
    )
    fts.index_content_item(content_id, text)

    entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
    fact_id = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object
    )
    store.insert_provenance(
      fact_id: fact_id,
      content_item_id: content_id,
      quote: text,
      strength: "stated"
    )

    {content_id: content_id, fact_id: fact_id, entity_id: entity_id}
  end

  describe "#query with intent" do
    before do
      create_content_with_fact(
        "Database migration from MySQL to PostgreSQL completed",
        "decision", "migrated to postgresql"
      )
      create_content_with_fact(
        "Database performance tuning with connection pooling",
        "convention", "use connection pooling"
      )
    end

    it "accepts intent parameter without error" do
      results = recall.query("database", intent: "migration")
      expect(results).to be_an(Array)
    end

    it "works with nil intent (no change in behavior)" do
      results_without = recall.query("database")
      results_with_nil = recall.query("database", intent: nil)
      expect(results_with_nil.size).to eq(results_without.size)
    end

    it "works with empty string intent (treated as nil)" do
      results = recall.query("database", intent: "")
      expect(results).to be_an(Array)
    end

    it "returns results when intent narrows the search" do
      results = recall.query("database", intent: "migration")
      expect(results).not_to be_empty
    end
  end

  describe "#query_index with intent" do
    before do
      create_content_with_fact(
        "Database schema migration strategy uses blue-green deployments",
        "decision", "blue-green migration"
      )
    end

    it "accepts intent parameter" do
      results = recall.query_index("database", intent: "migration")
      expect(results).to be_an(Array)
    end

    it "works without intent" do
      results = recall.query_index("database")
      expect(results).to be_an(Array)
    end
  end

  describe "#query_semantic with intent" do
    before do
      create_content_with_fact(
        "Authentication uses OAuth2 for security",
        "convention", "oauth2 authentication"
      )
    end

    it "accepts intent parameter" do
      results = recall.query_semantic("authentication", intent: "security", mode: :text)
      expect(results).to be_an(Array)
    end

    it "works without intent" do
      results = recall.query_semantic("authentication", mode: :text)
      expect(results).to be_an(Array)
    end
  end
end

RSpec.describe ClaudeMemory::Recall::QueryCore do
  # Test the intent_augmented_query helper via a test class
  let(:test_class) do
    Class.new do
      include ClaudeMemory::Recall::QueryCore

      public :intent_augmented_query
    end
  end
  let(:instance) { test_class.new }

  describe "#intent_augmented_query" do
    it "returns original query when intent is nil" do
      result = instance.intent_augmented_query("database", nil)
      expect(result).to eq("database")
    end

    it "returns original query when intent is empty string" do
      result = instance.intent_augmented_query("database", "")
      expect(result).to eq("database")
    end

    it "returns original query when intent is whitespace only" do
      result = instance.intent_augmented_query("database", "   ")
      expect(result).to eq("database")
    end

    it "appends intent to query" do
      result = instance.intent_augmented_query("database", "migration")
      expect(result).to eq("database migration")
    end

    it "strips whitespace from intent" do
      result = instance.intent_augmented_query("database", "  migration  ")
      expect(result).to eq("database migration")
    end

    it "augments query with intent" do
      result = instance.intent_augmented_query("database", "migration")
      expect(result).to eq("database migration")
    end
  end
end
