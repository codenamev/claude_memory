# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Store::SQLiteStore do
  let(:db_path) { File.join(Dir.tmpdir, "claude_memory_test_#{Process.pid}.sqlite3") }
  let(:store) { described_class.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#initialize" do
    it "creates the database file" do
      path = File.join(Dir.tmpdir, "claude_memory_init_test_#{Process.pid}.sqlite3")
      s = described_class.new(path)
      expect(File.exist?(path)).to be true
      s.close
      FileUtils.rm_f(path)
    end

    it "is idempotent" do
      store.close
      store2 = described_class.new(db_path)
      expect(store2.schema_version).to eq(described_class::SCHEMA_VERSION)
      store2.close
    end
  end

  describe "#schema_version" do
    it "returns the current schema version" do
      expect(store.schema_version).to eq(described_class::SCHEMA_VERSION)
    end
  end

  describe "table existence" do
    %w[meta content_items delta_cursors entities entity_aliases facts provenance fact_links conflicts].each do |table|
      it "creates #{table} table" do
        expect(store.db.table_exists?(table.to_sym)).to be true
      end
    end
  end

  describe "#upsert_content_item" do
    it "inserts a new content item" do
      id = store.upsert_content_item(
        source: "claude_code",
        session_id: "sess-123",
        transcript_path: "/path/to/transcript.jsonl",
        text_hash: "abc123",
        byte_len: 1000,
        raw_text: "some text",
        metadata: {foo: "bar"}
      )
      expect(id).to be > 0
    end

    it "returns existing id for duplicate text_hash + session_id" do
      attrs = {
        source: "claude_code",
        session_id: "sess-123",
        transcript_path: "/path/to/transcript.jsonl",
        text_hash: "abc123",
        byte_len: 1000,
        raw_text: "some text"
      }
      id1 = store.upsert_content_item(**attrs)
      id2 = store.upsert_content_item(**attrs)
      expect(id2).to eq(id1)
    end
  end

  describe "delta cursors" do
    it "returns nil for non-existent cursor" do
      expect(store.get_delta_cursor("unknown", "/path")).to be_nil
    end

    it "updates and retrieves cursor" do
      store.update_delta_cursor("sess-1", "/path/file", 500)
      expect(store.get_delta_cursor("sess-1", "/path/file")).to eq(500)
    end

    it "updates existing cursor" do
      store.update_delta_cursor("sess-1", "/path/file", 100)
      store.update_delta_cursor("sess-1", "/path/file", 200)
      expect(store.get_delta_cursor("sess-1", "/path/file")).to eq(200)
    end
  end

  describe "entities" do
    it "creates entity and returns id" do
      id = store.find_or_create_entity(type: "repo", name: "My Project")
      expect(id).to be > 0
    end

    it "finds existing entity by slug" do
      id1 = store.find_or_create_entity(type: "repo", name: "My Project")
      id2 = store.find_or_create_entity(type: "repo", name: "my project")
      expect(id2).to eq(id1)
    end

    it "creates different entities for different types" do
      id1 = store.find_or_create_entity(type: "repo", name: "auth")
      id2 = store.find_or_create_entity(type: "module", name: "auth")
      expect(id2).not_to eq(id1)
    end
  end

  describe "facts" do
    let!(:entity_id) { store.find_or_create_entity(type: "repo", name: "test") }

    it "inserts a fact" do
      id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "postgresql"
      )
      expect(id).to be > 0
    end

    it "retrieves facts for a slot" do
      store.insert_fact(subject_entity_id: entity_id, predicate: "uses_database", object_literal: "postgresql")
      store.insert_fact(subject_entity_id: entity_id, predicate: "deployment_platform", object_literal: "aws")

      facts = store.facts_for_slot(entity_id, "uses_database")
      expect(facts.size).to eq(1)
      expect(facts.first[:object_literal]).to eq("postgresql")
    end

    it "updates fact status" do
      id = store.insert_fact(subject_entity_id: entity_id, predicate: "uses_database", object_literal: "mysql")
      store.update_fact(id, status: "superseded", valid_to: Time.now.utc.iso8601)

      facts = store.facts_for_slot(entity_id, "uses_database", status: "superseded")
      expect(facts.size).to eq(1)
      expect(facts.first[:status]).to eq("superseded")
    end
  end

  describe "provenance" do
    let!(:entity_id) { store.find_or_create_entity(type: "repo", name: "test") }
    let!(:content_id) do
      store.upsert_content_item(
        source: "claude_code",
        session_id: "sess-1",
        text_hash: "hash1",
        byte_len: 100,
        raw_text: "context"
      )
    end
    let!(:fact_id) { store.insert_fact(subject_entity_id: entity_id, predicate: "convention", object_literal: "use snake_case") }

    it "inserts provenance record" do
      id = store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: "we decided to use snake_case",
        strength: "stated"
      )
      expect(id).to be > 0
    end

    it "retrieves provenance for a fact" do
      store.insert_provenance(fact_id: fact_id, content_item_id: content_id, quote: "the quote", strength: "stated")
      records = store.provenance_for_fact(fact_id)
      expect(records.size).to eq(1)
      expect(records.first[:quote]).to eq("the quote")
    end
  end

  describe "conflicts" do
    let!(:entity_id) { store.find_or_create_entity(type: "repo", name: "test") }
    let!(:fact_a_id) { store.insert_fact(subject_entity_id: entity_id, predicate: "uses_database", object_literal: "postgresql") }
    let!(:fact_b_id) { store.insert_fact(subject_entity_id: entity_id, predicate: "uses_database", object_literal: "mysql") }

    it "inserts a conflict" do
      id = store.insert_conflict(fact_a_id: fact_a_id, fact_b_id: fact_b_id, notes: "contradicting claims")
      expect(id).to be > 0
    end

    it "retrieves open conflicts" do
      store.insert_conflict(fact_a_id: fact_a_id, fact_b_id: fact_b_id)
      conflicts = store.open_conflicts
      expect(conflicts.size).to eq(1)
    end
  end

  describe "fact links" do
    let!(:entity_id) { store.find_or_create_entity(type: "repo", name: "test") }
    let!(:old_fact_id) { store.insert_fact(subject_entity_id: entity_id, predicate: "uses_database", object_literal: "mysql") }
    let!(:new_fact_id) { store.insert_fact(subject_entity_id: entity_id, predicate: "uses_database", object_literal: "postgresql") }

    it "inserts a fact link" do
      id = store.insert_fact_link(from_fact_id: new_fact_id, to_fact_id: old_fact_id, link_type: "supersedes")
      expect(id).to be > 0
    end
  end
end
