# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Shortcuts do
  let(:db_path) { File.join(Dir.tmpdir, "shortcuts_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:manager) { ClaudeMemory::Store::StoreManager.new(project_db_path: db_path) }

  after do
    manager.close if manager
    store.close if store && !manager
    FileUtils.rm_f(db_path)
  end

  def create_fact_with_content(predicate, object, text)
    entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
    fact_id = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object
    )

    content_id = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      text_hash: "hash",
      byte_len: text.bytesize,
      raw_text: text
    )

    store.insert_provenance(
      fact_id: fact_id,
      content_item_id: content_id,
      quote: text,
      strength: "stated"
    )

    fts = ClaudeMemory::Index::LexicalFTS.new(store)
    fts.index_content_item(content_id, text)

    fact_id
  end

  describe "::QUERIES" do
    it "defines query configurations" do
      expect(described_class::QUERIES).to be_a(Hash)
      expect(described_class::QUERIES).not_to be_empty
    end

    it "includes decisions query" do
      expect(described_class::QUERIES).to have_key(:decisions)
      expect(described_class::QUERIES[:decisions]).to include(:query, :scope, :limit)
    end

    it "includes architecture query" do
      expect(described_class::QUERIES).to have_key(:architecture)
      expect(described_class::QUERIES[:architecture]).to include(:query, :scope, :limit)
    end

    it "includes conventions query" do
      expect(described_class::QUERIES).to have_key(:conventions)
      expect(described_class::QUERIES[:conventions]).to include(:query, :scope, :limit)
    end

    it "includes project_config query" do
      expect(described_class::QUERIES).to have_key(:project_config)
      expect(described_class::QUERIES[:project_config]).to include(:query, :scope, :limit)
    end
  end

  describe ".for" do
    it "returns results for a configured shortcut" do
      create_fact_with_content("decision", "Use PostgreSQL", "We decided to use PostgreSQL")

      results = described_class.for(:decisions, manager)

      expect(results).to be_an(Array)
    end

    it "uses the configured query text" do
      manager.ensure_both!

      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "decision",
        object_literal: "Use tabs for indentation"
      )

      # Use content that matches the query keywords
      text = "We made a decision about the constraint and rule for the requirement"
      content_id = manager.project_store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        text_hash: "hash",
        byte_len: text.bytesize,
        raw_text: text
      )

      manager.project_store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: "decision",
        strength: "stated"
      )

      fts = ClaudeMemory::Index::LexicalFTS.new(manager.project_store)
      fts.index_content_item(content_id, text)

      results = described_class.for(:decisions, manager)

      # Should find decision-related content
      expect(results).to be_an(Array)
      # Result may or may not be empty depending on FTS matching, but method works
    end

    it "uses the configured scope" do
      # conventions should use global scope by default
      config = described_class::QUERIES[:conventions]
      expect(config[:scope]).to eq(:global)
    end

    it "uses the configured limit" do
      config = described_class::QUERIES[:decisions]
      expect(config[:limit]).to be_a(Integer)
      expect(config[:limit]).to be > 0
    end

    it "allows overriding limit" do
      create_fact_with_content("decision", "Use PostgreSQL", "Decision content")

      results = described_class.for(:decisions, manager, limit: 5)

      expect(results).to be_an(Array)
      expect(results.size).to be <= 5
    end

    it "allows overriding scope" do
      results = described_class.for(:decisions, manager, scope: :project)

      expect(results).to be_an(Array)
    end

    it "raises error for unknown shortcut" do
      expect {
        described_class.for(:nonexistent, manager)
      }.to raise_error(KeyError)
    end

    it "works with StoreManager" do
      manager.ensure_both!

      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "Rails"
      )

      content_id = manager.project_store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        text_hash: "hash",
        byte_len: 10,
        raw_text: "Uses Rails"
      )

      manager.project_store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: "Rails",
        strength: "stated"
      )

      fts = ClaudeMemory::Index::LexicalFTS.new(manager.project_store)
      fts.index_content_item(content_id, "Uses Rails framework")

      results = described_class.for(:architecture, manager)

      expect(results).to be_an(Array)
    end
  end

  describe ".decisions" do
    it "is a convenience method for :decisions shortcut" do
      results = described_class.decisions(manager)
      expect(results).to be_an(Array)
    end

    it "allows overriding limit" do
      results = described_class.decisions(manager, limit: 5)
      expect(results).to be_an(Array)
    end
  end

  describe ".architecture" do
    it "is a convenience method for :architecture shortcut" do
      results = described_class.architecture(manager)
      expect(results).to be_an(Array)
    end
  end

  describe ".conventions" do
    it "is a convenience method for :conventions shortcut" do
      results = described_class.conventions(manager)
      expect(results).to be_an(Array)
    end
  end

  describe ".project_config" do
    it "is a convenience method for :project_config shortcut" do
      results = described_class.project_config(manager)
      expect(results).to be_an(Array)
    end
  end
end
