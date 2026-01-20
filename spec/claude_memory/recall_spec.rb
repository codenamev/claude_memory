# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Recall do
  let(:db_path) { File.join(Dir.tmpdir, "recall_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:fts) { ClaudeMemory::Index::LexicalFTS.new(store) }
  let(:recall) { described_class.new(store, fts: fts) }

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

  describe "#query" do
    it "returns empty for no matches" do
      results = recall.query("nonexistent")
      expect(results).to be_empty
    end

    it "returns facts with receipts for matching content" do
      create_content_with_fact("We use PostgreSQL for the database", "uses_database", "postgresql")

      results = recall.query("PostgreSQL")
      expect(results.size).to eq(1)
      expect(results.first[:fact][:predicate]).to eq("uses_database")
      expect(results.first[:receipts]).not_to be_empty
    end

    it "respects limit" do
      3.times do |i|
        create_content_with_fact("Fact #{i} about databases", "convention", "rule_#{i}")
      end

      results = recall.query("databases", limit: 2)
      expect(results.size).to be <= 2
    end

    it "deduplicates facts" do
      data = create_content_with_fact("PostgreSQL is great", "uses_database", "postgresql")
      store.insert_provenance(
        fact_id: data[:fact_id],
        content_item_id: data[:content_id],
        quote: "Another quote about PostgreSQL",
        strength: "inferred"
      )

      results = recall.query("PostgreSQL")
      expect(results.size).to eq(1)
    end
  end

  describe "#explain" do
    it "returns nil for non-existent fact" do
      expect(recall.explain(999)).to be_nil
    end

    it "returns fact with receipts" do
      data = create_content_with_fact("We use Rails", "uses_framework", "rails")

      explanation = recall.explain(data[:fact_id])
      expect(explanation[:fact][:predicate]).to eq("uses_framework")
      expect(explanation[:receipts].size).to eq(1)
      expect(explanation[:receipts].first[:quote]).to eq("We use Rails")
    end

    it "includes supersession links" do
      data1 = create_content_with_fact("Using MySQL", "uses_database", "mysql")
      data2 = create_content_with_fact("Switched to PostgreSQL", "uses_database", "postgresql")
      store.insert_fact_link(from_fact_id: data2[:fact_id], to_fact_id: data1[:fact_id], link_type: "supersedes")

      explanation = recall.explain(data2[:fact_id])
      expect(explanation[:supersedes]).to include(data1[:fact_id])
    end

    it "includes conflict records" do
      data1 = create_content_with_fact("Using MySQL", "uses_database", "mysql")
      data2 = create_content_with_fact("Using PostgreSQL", "uses_database", "postgresql")
      store.insert_conflict(fact_a_id: data1[:fact_id], fact_b_id: data2[:fact_id])

      explanation = recall.explain(data1[:fact_id])
      expect(explanation[:conflicts]).not_to be_empty
    end
  end

  describe "#changes" do
    it "returns recent facts" do
      create_content_with_fact("Convention 1", "convention", "rule1")
      sleep 0.01
      create_content_with_fact("Convention 2", "convention", "rule2")

      yesterday = (Time.now - 86400).utc.iso8601
      changes = recall.changes(since: yesterday)
      expect(changes.size).to eq(2)
    end

    it "filters by since timestamp" do
      create_content_with_fact("Old convention", "convention", "old_rule")

      future = (Time.now + 86400).utc.iso8601
      changes = recall.changes(since: future)
      expect(changes).to be_empty
    end
  end
end
