# frozen_string_literal: true

require "spec_helper"
require "claude_memory/ingest/ingester"
require "claude_memory/store/sqlite_store"
require "claude_memory/index/lexical_fts"
require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Ingest::Ingester, "atomicity" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "test.sqlite3") }
  let(:transcript_path) { File.join(temp_dir, "transcript.jsonl") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:fts) { ClaudeMemory::Index::LexicalFTS.new(store) }
  let(:ingester) { described_class.new(store, fts: fts) }
  let(:session_id) { "test-session-123" }

  before do
    # Create test transcript file
    File.write(transcript_path, '{"role": "user", "content": "Hello world"}' + "\n")
  end

  after do
    store.close
    FileUtils.rm_rf(temp_dir)
  end

  describe "transaction wrapping" do
    it "commits all operations atomically on success" do
      result = ingester.ingest(
        source: "test",
        session_id: session_id,
        transcript_path: transcript_path
      )

      expect(result[:status]).to eq(:ingested)

      # Verify content was inserted
      content = store.content_items.where(id: result[:content_id]).first
      expect(content).not_to be_nil
      expect(content[:raw_text]).to include("Hello world")

      # Verify cursor was updated
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be > 0

      # Verify FTS index was created
      indexed = store.db[:content_fts].where(content_item_id: result[:content_id]).first
      expect(indexed).not_to be_nil
    end

    it "rolls back content insertion if FTS indexing fails" do
      # Stub FTS to fail
      allow(fts).to receive(:index_content_item).and_raise(StandardError, "FTS indexing failed")

      # Ingestion should fail
      expect {
        ingester.ingest(
          source: "test",
          session_id: session_id,
          transcript_path: transcript_path
        )
      }.to raise_error(StandardError, /Ingestion failed/)

      # Verify content was NOT inserted (rollback occurred)
      content = store.content_items.where(session_id: session_id).first
      expect(content).to be_nil

      # Verify cursor was NOT updated
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be_nil

      # Verify FTS index was NOT created
      indexed_count = store.db[:content_fts].count
      expect(indexed_count).to eq(0)
    end

    it "rolls back all operations if cursor update fails" do
      # Stub cursor update to fail
      allow(store).to receive(:update_delta_cursor).and_raise(StandardError, "Cursor update failed")

      # Ingestion should fail
      expect {
        ingester.ingest(
          source: "test",
          session_id: session_id,
          transcript_path: transcript_path
        )
      }.to raise_error(StandardError, /Ingestion failed/)

      # Verify content was NOT inserted (rollback occurred)
      content = store.content_items.where(session_id: session_id).first
      expect(content).to be_nil

      # Verify FTS index was NOT created
      indexed_count = store.db[:content_fts].count
      expect(indexed_count).to eq(0)
    end

    it "does not advance cursor if content insertion fails" do
      # Stub content insertion to fail
      allow(store).to receive(:upsert_content_item).and_raise(StandardError, "Content insertion failed")

      # Ingestion should fail
      expect {
        ingester.ingest(
          source: "test",
          session_id: session_id,
          transcript_path: transcript_path
        )
      }.to raise_error(StandardError, /Ingestion failed/)

      # Verify cursor was NOT updated (stayed at default/nil)
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be_nil

      # On retry, ingestion should start from beginning
      allow(store).to receive(:upsert_content_item).and_call_original

      result = ingester.ingest(
        source: "test",
        session_id: session_id,
        transcript_path: transcript_path
      )

      expect(result[:status]).to eq(:ingested)

      # Verify cursor is now updated
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be > 0
    end
  end

  describe "cursor consistency" do
    it "allows retry after FTS failure without re-processing" do
      # First attempt - FTS fails
      allow(fts).to receive(:index_content_item).and_raise(StandardError, "FTS failure")

      expect {
        ingester.ingest(
          source: "test",
          session_id: session_id,
          transcript_path: transcript_path
        )
      }.to raise_error(StandardError, /Ingestion failed/)

      # Verify cursor is still at 0 (or nil)
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be_nil

      # Second attempt - FTS succeeds
      allow(fts).to receive(:index_content_item).and_call_original

      result = ingester.ingest(
        source: "test",
        session_id: session_id,
        transcript_path: transcript_path
      )

      expect(result[:status]).to eq(:ingested)

      # Verify cursor advanced
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be > 0

      # Verify only one content item was created (no duplicate)
      content_count = store.content_items.where(session_id: session_id).count
      expect(content_count).to eq(1)
    end

    it "maintains consistency across multiple operations" do
      # This test verifies that successful operations maintain consistency
      # First ingestion succeeds
      result1 = ingester.ingest(
        source: "test",
        session_id: session_id,
        transcript_path: transcript_path
      )

      expect(result1[:status]).to eq(:ingested)
      first_cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(first_cursor).to be > 0

      # Verify content and cursor are in sync
      content = store.content_items.where(id: result1[:content_id]).first
      expect(content).not_to be_nil

      # Cursor should point to end of processed content
      cursor_value = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor_value).to eq(first_cursor)
    end
  end

  describe "incremental ingestion with atomicity" do
    it "verifies transaction ensures all-or-nothing behavior" do
      # This test verifies that the transaction wrapper provides atomicity
      # by checking that successful operations commit all changes together

      result = ingester.ingest(
        source: "test",
        session_id: session_id,
        transcript_path: transcript_path
      )

      expect(result[:status]).to eq(:ingested)

      # All operations should have succeeded atomically:
      # 1. Content item was created
      content = store.content_items.where(id: result[:content_id]).first
      expect(content).not_to be_nil

      # 2. FTS index was created
      fts_entry = store.db[:content_fts].where(content_item_id: result[:content_id]).first
      expect(fts_entry).not_to be_nil

      # 3. Cursor was updated
      cursor = store.get_delta_cursor(session_id, transcript_path)
      expect(cursor).to be > 0

      # All three operations happened in one atomic transaction
    end
  end

  describe "error context" do
    it "provides meaningful error messages on failure" do
      allow(fts).to receive(:index_content_item).and_raise(StandardError, "FTS internal error")

      expect {
        ingester.ingest(
          source: "test",
          session_id: session_id,
          transcript_path: transcript_path
        )
      }.to raise_error(StandardError, /Ingestion failed for session test-session-123: FTS internal error/)
    end
  end
end
