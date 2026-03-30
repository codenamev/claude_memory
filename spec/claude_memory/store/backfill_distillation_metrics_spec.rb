# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "digest"

RSpec.describe ClaudeMemory::Store::SQLiteStore, "#backfill_distillation_metrics!" do
  let(:db_path) { File.join(Dir.tmpdir, "claude_memory_backfill_test_#{Process.pid}.sqlite3") }
  let(:store) { described_class.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def insert_content_item(session_id:, text:)
    store.upsert_content_item(
      session_id: session_id,
      source: "test",
      raw_text: text,
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize
    )
  end

  context "with content items missing ingestion_metrics" do
    before do
      insert_content_item(session_id: "s1", text: "first content")
      insert_content_item(session_id: "s2", text: "second content")
      insert_content_item(session_id: "s3", text: "third content")
    end

    it "creates ingestion_metrics rows for all undistilled items" do
      count = store.backfill_distillation_metrics!
      expect(count).to eq(3)
      expect(store.ingestion_metrics.count).to eq(3)
    end

    it "marks backfilled items with zero tokens and facts" do
      store.backfill_distillation_metrics!

      store.ingestion_metrics.all.each do |row|
        expect(row[:input_tokens]).to eq(0)
        expect(row[:output_tokens]).to eq(0)
        expect(row[:facts_extracted]).to eq(0)
      end
    end

    it "makes count_undistilled return 0 after backfill" do
      expect(store.count_undistilled(min_length: 0)).to eq(3)
      store.backfill_distillation_metrics!
      expect(store.count_undistilled(min_length: 0)).to eq(0)
    end
  end

  context "idempotency" do
    before do
      insert_content_item(session_id: "s1", text: "some content")
    end

    it "returns 0 on second run without duplicating rows" do
      first_count = store.backfill_distillation_metrics!
      expect(first_count).to eq(1)

      second_count = store.backfill_distillation_metrics!
      expect(second_count).to eq(0)
      expect(store.ingestion_metrics.count).to eq(1)
    end
  end

  context "with mixed distilled and undistilled items" do
    before do
      id1 = insert_content_item(session_id: "s1", text: "already tracked")
      insert_content_item(session_id: "s2", text: "not yet tracked")

      # Manually add metrics for the first item
      store.record_ingestion_metrics(
        content_item_id: id1,
        input_tokens: 100,
        output_tokens: 50,
        facts_extracted: 2
      )
    end

    it "only backfills items without metrics" do
      count = store.backfill_distillation_metrics!
      expect(count).to eq(1)
      expect(store.ingestion_metrics.count).to eq(2)
    end

    it "does not overwrite existing metrics" do
      store.backfill_distillation_metrics!

      existing = store.ingestion_metrics.order(:id).first
      expect(existing[:input_tokens]).to eq(100)
      expect(existing[:facts_extracted]).to eq(2)
    end
  end

  context "with no content items" do
    it "returns 0" do
      count = store.backfill_distillation_metrics!
      expect(count).to eq(0)
    end
  end
end
