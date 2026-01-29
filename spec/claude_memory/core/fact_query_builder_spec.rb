# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/fact_query_builder"

RSpec.describe ClaudeMemory::Core::FactQueryBuilder do
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(":memory:") }
  let(:entity_id) { store.find_or_create_entity(type: "repo", name: "MyRepo") }
  let(:content_id) { store.upsert_content_item(source: "test", text_hash: "hash1", byte_len: 100, session_id: "sess1", occurred_at: Time.now) }

  before do
    # Insert test data
    @fact_id_1 = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: "uses_database",
      object_literal: "PostgreSQL",
      scope: "project",
      project_path: "/test"
    )

    @fact_id_2 = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: "uses_framework",
      object_literal: "Rails",
      scope: "global"
    )

    store.insert_provenance(fact_id: @fact_id_1, content_item_id: content_id, quote: "uses postgres", strength: "stated")
    store.insert_provenance(fact_id: @fact_id_2, content_item_id: content_id, quote: "rails app", strength: "inferred")
  end

  describe ".batch_find_facts" do
    it "returns hash of fact_id => fact_row" do
      results = described_class.batch_find_facts(store, [@fact_id_1, @fact_id_2])

      expect(results).to be_a(Hash)
      expect(results[@fact_id_1]).to be_a(Hash)
      expect(results[@fact_id_1][:predicate]).to eq("uses_database")
      expect(results[@fact_id_2][:predicate]).to eq("uses_framework")
    end

    it "includes subject_name from entity join" do
      results = described_class.batch_find_facts(store, [@fact_id_1])

      expect(results[@fact_id_1][:subject_name]).to eq("MyRepo")
    end

    it "includes scope and project_path" do
      results = described_class.batch_find_facts(store, [@fact_id_1, @fact_id_2])

      expect(results[@fact_id_1][:scope]).to eq("project")
      expect(results[@fact_id_1][:project_path]).to eq("/test")
      expect(results[@fact_id_2][:scope]).to eq("global")
    end

    it "returns empty hash for empty fact_ids" do
      results = described_class.batch_find_facts(store, [])

      expect(results).to eq({})
    end

    it "returns only existing facts" do
      results = described_class.batch_find_facts(store, [@fact_id_1, 9999])

      expect(results.keys).to eq([@fact_id_1])
    end
  end

  describe ".batch_find_receipts" do
    it "returns hash of fact_id => [receipt_rows]" do
      results = described_class.batch_find_receipts(store, [@fact_id_1, @fact_id_2])

      expect(results).to be_a(Hash)
      expect(results[@fact_id_1]).to be_an(Array)
      expect(results[@fact_id_1].first[:quote]).to eq("uses postgres")
      expect(results[@fact_id_2].first[:quote]).to eq("rails app")
    end

    it "includes session_id from content_items join" do
      results = described_class.batch_find_receipts(store, [@fact_id_1])

      expect(results[@fact_id_1].first[:session_id]).to eq("sess1")
    end

    it "includes strength" do
      results = described_class.batch_find_receipts(store, [@fact_id_1, @fact_id_2])

      expect(results[@fact_id_1].first[:strength]).to eq("stated")
      expect(results[@fact_id_2].first[:strength]).to eq("inferred")
    end

    it "returns empty hash for empty fact_ids" do
      results = described_class.batch_find_receipts(store, [])

      expect(results).to eq({})
    end

    it "returns empty array for facts with no receipts" do
      fact_id_3 = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test",
        object_literal: "value"
      )

      results = described_class.batch_find_receipts(store, [fact_id_3])

      expect(results[fact_id_3]).to eq([])
    end
  end

  describe ".find_fact" do
    it "returns single fact by ID" do
      fact = described_class.find_fact(store, @fact_id_1)

      expect(fact).to be_a(Hash)
      expect(fact[:id]).to eq(@fact_id_1)
      expect(fact[:predicate]).to eq("uses_database")
    end

    it "includes subject_name from entity join" do
      fact = described_class.find_fact(store, @fact_id_1)

      expect(fact[:subject_name]).to eq("MyRepo")
    end

    it "returns nil for non-existent fact" do
      fact = described_class.find_fact(store, 9999)

      expect(fact).to be_nil
    end
  end

  describe ".find_receipts" do
    it "returns receipts for single fact" do
      receipts = described_class.find_receipts(store, @fact_id_1)

      expect(receipts).to be_an(Array)
      expect(receipts.size).to eq(1)
      expect(receipts.first[:quote]).to eq("uses postgres")
    end

    it "includes session_id from content_items join" do
      receipts = described_class.find_receipts(store, @fact_id_1)

      expect(receipts.first[:session_id]).to eq("sess1")
    end

    it "returns empty array for fact with no receipts" do
      fact_id_3 = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test",
        object_literal: "value"
      )

      receipts = described_class.find_receipts(store, fact_id_3)

      expect(receipts).to eq([])
    end
  end

  describe ".find_superseded_by" do
    it "returns fact IDs that supersede the given fact" do
      superseding_fact = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "MySQL"
      )
      store.insert_fact_link(from_fact_id: superseding_fact, to_fact_id: @fact_id_1, link_type: "supersedes")

      result = described_class.find_superseded_by(store, @fact_id_1)

      expect(result).to eq([superseding_fact])
    end

    it "returns empty array when no superseding facts" do
      result = described_class.find_superseded_by(store, @fact_id_1)

      expect(result).to eq([])
    end
  end

  describe ".find_supersedes" do
    it "returns fact IDs that are superseded by the given fact" do
      old_fact = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "SQLite"
      )
      store.insert_fact_link(from_fact_id: @fact_id_1, to_fact_id: old_fact, link_type: "supersedes")

      result = described_class.find_supersedes(store, @fact_id_1)

      expect(result).to eq([old_fact])
    end

    it "returns empty array when fact doesn't supersede anything" do
      result = described_class.find_supersedes(store, @fact_id_1)

      expect(result).to eq([])
    end
  end

  describe ".find_conflicts" do
    it "returns conflicts involving the fact" do
      conflict_id = store.insert_conflict(fact_a_id: @fact_id_1, fact_b_id: @fact_id_2)

      result = described_class.find_conflicts(store, @fact_id_1)

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first[:id]).to eq(conflict_id)
      expect(result.first[:fact_a_id]).to eq(@fact_id_1)
      expect(result.first[:fact_b_id]).to eq(@fact_id_2)
    end

    it "returns conflicts where fact is either fact_a or fact_b" do
      store.insert_conflict(fact_a_id: @fact_id_1, fact_b_id: @fact_id_2)
      store.insert_conflict(fact_a_id: @fact_id_2, fact_b_id: @fact_id_1)

      result = described_class.find_conflicts(store, @fact_id_1)

      expect(result.size).to eq(2)
    end

    it "returns empty array when no conflicts" do
      result = described_class.find_conflicts(store, @fact_id_1)

      expect(result).to eq([])
    end
  end

  describe ".fetch_changes" do
    it "returns facts created since timestamp" do
      # Use a timestamp well in the past
      cutoff = Time.now - 3600  # 1 hour ago

      result = described_class.fetch_changes(store, cutoff, 10)

      # Should include facts from before block
      expect(result.map { |r| r[:id] }).to include(@fact_id_1, @fact_id_2)
      expect(result.size).to be >= 2
    end

    it "orders by created_at descending" do
      # Get all facts
      result = described_class.fetch_changes(store, Time.now - 3600, 10)

      # Verify results are ordered by created_at descending
      timestamps = result.map { |r| r[:created_at] }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end

    it "respects limit" do
      now = Time.now - 1
      result = described_class.fetch_changes(store, now, 1)

      expect(result.size).to eq(1)
    end

    it "includes scope and project_path" do
      now = Time.now - 1
      result = described_class.fetch_changes(store, now, 10)

      fact = result.find { |r| r[:id] == @fact_id_1 }
      expect(fact[:scope]).to eq("project")
      expect(fact[:project_path]).to eq("/test")
    end
  end

  describe ".find_provenance_by_content" do
    it "returns provenance records for content item" do
      result = described_class.find_provenance_by_content(store, content_id)

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.map { |r| r[:fact_id] }).to contain_exactly(@fact_id_1, @fact_id_2)
    end

    it "includes quote and strength" do
      result = described_class.find_provenance_by_content(store, content_id)

      prov = result.find { |r| r[:fact_id] == @fact_id_1 }
      expect(prov[:quote]).to eq("uses postgres")
      expect(prov[:strength]).to eq("stated")
    end

    it "returns empty array for content with no provenance" do
      empty_content = store.upsert_content_item(source: "test", text_hash: "hash2", byte_len: 100, session_id: "sess2", occurred_at: Time.now)

      result = described_class.find_provenance_by_content(store, empty_content)

      expect(result).to eq([])
    end
  end

  describe ".build_facts_dataset" do
    it "builds dataset with entity join" do
      dataset = described_class.build_facts_dataset(store)

      expect(dataset).to be_a(Sequel::Dataset)
      # Verify it can be executed
      results = dataset.all
      expect(results).to be_an(Array)
    end

    it "includes all required columns" do
      dataset = described_class.build_facts_dataset(store)
      row = dataset.first

      expect(row.keys).to include(:id, :predicate, :object_literal, :status, :confidence, :subject_name, :scope, :project_path)
    end
  end

  describe ".build_receipts_dataset" do
    it "builds dataset with content_items join" do
      dataset = described_class.build_receipts_dataset(store)

      expect(dataset).to be_a(Sequel::Dataset)
      # Verify it can be executed
      results = dataset.all
      expect(results).to be_an(Array)
    end

    it "includes all required columns" do
      dataset = described_class.build_receipts_dataset(store)
      row = dataset.first

      expect(row.keys).to include(:id, :fact_id, :quote, :strength, :session_id, :occurred_at)
    end
  end
end
