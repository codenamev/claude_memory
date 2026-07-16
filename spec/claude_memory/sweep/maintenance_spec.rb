# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "securerandom"

RSpec.describe ClaudeMemory::Sweep::Maintenance do
  let(:db_path) { File.join(Dir.tmpdir, "maintenance_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:maintenance) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_fact(status:, days_ago:)
    entity_id = store.find_or_create_entity(type: "repo", name: "test")
    created_at = (Time.now - days_ago * 86400).utc.iso8601
    store.facts.insert(
      subject_entity_id: entity_id,
      predicate: "test_pred",
      object_literal: "test_obj",
      status: status,
      created_at: created_at
    )
  end

  def create_content(days_ago:)
    ingested_at = (Time.now - days_ago * 86400).utc.iso8601
    store.content_items.insert(
      source: "test",
      ingested_at: ingested_at,
      text_hash: SecureRandom.hex(16),
      byte_len: 100,
      raw_text: "test content"
    )
  end

  describe "#expire_proposed_facts" do
    it "returns count of expired facts" do
      create_fact(status: "proposed", days_ago: 20)
      create_fact(status: "proposed", days_ago: 20)
      expect(maintenance.expire_proposed_facts).to eq(2)
    end

    it "does not expire recent proposed facts" do
      create_fact(status: "proposed", days_ago: 5)
      expect(maintenance.expire_proposed_facts).to eq(0)
    end

    it "does not expire active facts" do
      create_fact(status: "active", days_ago: 20)
      expect(maintenance.expire_proposed_facts).to eq(0)
    end
  end

  describe "#expire_disputed_facts" do
    it "returns count of expired facts" do
      create_fact(status: "disputed", days_ago: 35)
      expect(maintenance.expire_disputed_facts).to eq(1)
    end

    it "does not expire recent disputed facts" do
      create_fact(status: "disputed", days_ago: 20)
      expect(maintenance.expire_disputed_facts).to eq(0)
    end
  end

  describe "#prune_orphaned_provenance" do
    it "returns count of deleted provenance" do
      store.db.run("PRAGMA foreign_keys = OFF")
      store.provenance.insert(fact_id: 99999, quote: "orphaned", strength: "stated")
      store.db.run("PRAGMA foreign_keys = ON")

      expect(maintenance.prune_orphaned_provenance).to eq(1)
    end

    it "returns 0 when no orphans exist" do
      expect(maintenance.prune_orphaned_provenance).to eq(0)
    end
  end

  describe "#prune_old_content" do
    it "returns count of pruned content items" do
      create_content(days_ago: 35)
      expect(maintenance.prune_old_content).to eq(1)
    end

    it "preserves content with provenance links" do
      content_id = create_content(days_ago: 35)
      fact_id = create_fact(status: "active", days_ago: 1)
      store.insert_provenance(fact_id: fact_id, content_item_id: content_id, quote: "test")

      expect(maintenance.prune_old_content).to eq(0)
    end

    it "preserves recent content" do
      create_content(days_ago: 10)
      expect(maintenance.prune_old_content).to eq(0)
    end
  end

  describe "#backfill_vec_index" do
    it "returns 0 when vector index is unavailable" do
      expect(maintenance.backfill_vec_index).to eq(0)
    end
  end

  describe "#cleanup_vec_expired" do
    it "returns 0 when vector index is unavailable" do
      expect(maintenance.cleanup_vec_expired).to eq(0)
    end
  end

  describe "#checkpoint_wal" do
    it "returns true" do
      expect(maintenance.checkpoint_wal).to be true
    end
  end

  describe "#vacuum" do
    it "returns true" do
      expect(maintenance.vacuum).to be true
    end
  end

  describe "#prune_old_mcp_tool_calls" do
    def create_mcp_call(days_ago:, tool_name: "memory.recall")
      called_at = (Time.now - days_ago * 86400).utc.iso8601
      store.insert_mcp_tool_call(
        tool_name: tool_name,
        duration_ms: 5,
        result_count: 1,
        called_at: called_at
      )
    end

    it "deletes rows older than the retention window and keeps recent ones" do
      create_mcp_call(days_ago: 120)
      create_mcp_call(days_ago: 100)
      create_mcp_call(days_ago: 10)

      deleted = maintenance.prune_old_mcp_tool_calls
      expect(deleted).to eq(2)
      expect(store.mcp_tool_calls.count).to eq(1)
    end

    it "respects a custom retention window" do
      custom = described_class.new(store, config: {mcp_tool_call_retention_days: 7})
      create_mcp_call(days_ago: 30)
      create_mcp_call(days_ago: 3)

      expect(custom.prune_old_mcp_tool_calls).to eq(1)
      expect(store.mcp_tool_calls.count).to eq(1)
    end
  end

  describe "custom config" do
    it "respects custom TTLs" do
      custom = described_class.new(store, config: {proposed_fact_ttl_days: 5})
      create_fact(status: "proposed", days_ago: 10)
      expect(custom.expire_proposed_facts).to eq(1)
    end
  end

  describe "#repair_fts_rank (improvement #69 — FTS self-heal)" do
    def index_content(text)
      id = store.upsert_content_item(
        source: "claude_code", session_id: "s",
        text_hash: Digest::SHA256.hexdigest(text), byte_len: text.bytesize, raw_text: text
      )
      ClaudeMemory::Index::LexicalFTS.new(store).index_content_item(id, text)
    end

    it "returns false (no rebuild) when the rank path is healthy" do
      index_content("the project uses sqlite")
      expect(maintenance.repair_fts_rank).to be false
    end

    it "rebuilds the FTS index and returns true when the rank path is corrupt" do
      index_content("the project uses sqlite")
      allow_any_instance_of(ClaudeMemory::Index::LexicalFTS).to receive(:search)
        .and_raise(ClaudeMemory::Index::LexicalFTS::CorruptRankIndexError, "corrupt")
      expect_any_instance_of(ClaudeMemory::Index::LexicalFTS).to receive(:rebuild!)

      expect(maintenance.repair_fts_rank).to be true
    end
  end
end
