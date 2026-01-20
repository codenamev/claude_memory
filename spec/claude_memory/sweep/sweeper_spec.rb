# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "securerandom"

RSpec.describe ClaudeMemory::Sweep::Sweeper do
  let(:db_path) { File.join(Dir.tmpdir, "sweeper_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:sweeper) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_fact(status:, days_ago:)
    entity_id = store.find_or_create_entity(type: "repo", name: "test")
    created_at = (Time.now - days_ago * 86400).utc.iso8601
    store.db.execute(
      "INSERT INTO facts (subject_entity_id, predicate, object_literal, status, created_at) VALUES (?, ?, ?, ?, ?)",
      [entity_id, "test_pred", "test_obj", status, created_at]
    )
    store.db.last_insert_row_id
  end

  def create_content(days_ago:)
    ingested_at = (Time.now - days_ago * 86400).utc.iso8601
    store.db.execute(
      "INSERT INTO content_items (source, ingested_at, text_hash, byte_len, raw_text) VALUES (?, ?, ?, ?, ?)",
      ["test", ingested_at, SecureRandom.hex(16), 100, "test content"]
    )
    store.db.last_insert_row_id
  end

  describe "#run!" do
    it "returns stats" do
      stats = sweeper.run!
      expect(stats).to include(:proposed_facts_expired, :disputed_facts_expired, :elapsed_seconds)
    end

    it "honors budget" do
      stats = sweeper.run!(budget_seconds: 10)
      expect(stats[:budget_honored]).to be true
    end

    context "proposed facts expiration" do
      it "expires old proposed facts" do
        create_fact(status: "proposed", days_ago: 20)
        stats = sweeper.run!
        expect(stats[:proposed_facts_expired]).to eq(1)
      end

      it "does not expire recent proposed facts" do
        create_fact(status: "proposed", days_ago: 5)
        stats = sweeper.run!
        expect(stats[:proposed_facts_expired]).to eq(0)
      end

      it "does not expire active facts" do
        create_fact(status: "active", days_ago: 20)
        stats = sweeper.run!
        expect(stats[:proposed_facts_expired]).to eq(0)
      end
    end

    context "disputed facts expiration" do
      it "expires old disputed facts" do
        create_fact(status: "disputed", days_ago: 35)
        stats = sweeper.run!
        expect(stats[:disputed_facts_expired]).to eq(1)
      end

      it "does not expire recent disputed facts" do
        create_fact(status: "disputed", days_ago: 20)
        stats = sweeper.run!
        expect(stats[:disputed_facts_expired]).to eq(0)
      end
    end

    context "orphaned provenance" do
      it "deletes provenance for deleted facts" do
        fact_id = create_fact(status: "active", days_ago: 1)
        store.insert_provenance(fact_id: fact_id, quote: "test")
        store.execute("DELETE FROM facts WHERE id = ?", [fact_id])

        stats = sweeper.run!
        expect(stats[:orphaned_provenance_deleted]).to eq(1)
      end
    end

    context "old content pruning" do
      it "prunes unreferenced old content" do
        create_content(days_ago: 35)
        stats = sweeper.run!
        expect(stats[:old_content_pruned]).to eq(1)
      end

      it "does not prune content with provenance" do
        content_id = create_content(days_ago: 35)
        fact_id = create_fact(status: "active", days_ago: 1)
        store.insert_provenance(fact_id: fact_id, content_item_id: content_id, quote: "test")

        stats = sweeper.run!
        expect(stats[:old_content_pruned]).to eq(0)
      end

      it "does not prune recent content" do
        create_content(days_ago: 10)
        stats = sweeper.run!
        expect(stats[:old_content_pruned]).to eq(0)
      end
    end

    context "custom config" do
      it "respects custom TTLs" do
        custom_sweeper = described_class.new(store, config: {proposed_fact_ttl_days: 5})
        create_fact(status: "proposed", days_ago: 10)
        stats = custom_sweeper.run!
        expect(stats[:proposed_facts_expired]).to eq(1)
      end
    end
  end
end
