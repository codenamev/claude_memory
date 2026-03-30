# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "digest"

RSpec.describe ClaudeMemory::Commands::Checks::DistillCheck do
  let(:test_dir) { File.join(Dir.tmpdir, "distill_check_test_#{Process.pid}") }
  let(:db_path) { File.join(test_dir, "memory.sqlite3") }

  before { FileUtils.mkdir_p(test_dir) }

  after { FileUtils.rm_rf(test_dir) }

  describe "#call" do
    context "when database does not exist" do
      it "returns ok status" do
        check = described_class.new(File.join(test_dir, "nonexistent.sqlite3"), "project")
        result = check.call

        expect(result[:status]).to eq(:ok)
        expect(result[:label]).to eq("project_distill")
      end
    end

    context "when all content items have metrics" do
      it "returns ok status" do
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        id = store.upsert_content_item(
          session_id: "s1",
          source: "test",
          raw_text: "test content",
          text_hash: Digest::SHA256.hexdigest("test content"),
          byte_len: 12
        )
        store.record_ingestion_metrics(
          content_item_id: id,
          input_tokens: 0,
          output_tokens: 0,
          facts_extracted: 0
        )
        store.close

        check = described_class.new(db_path, "project")
        result = check.call

        expect(result[:status]).to eq(:ok)
        expect(result[:details][:undistilled_count]).to eq(0)
        expect(result[:warnings]).to be_empty
      end
    end

    context "when content items are missing metrics" do
      it "returns warning status" do
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        store.upsert_content_item(
          session_id: "s1",
          source: "test",
          raw_text: "test content",
          text_hash: Digest::SHA256.hexdigest("test content"),
          byte_len: 12
        )
        store.upsert_content_item(
          session_id: "s2",
          source: "test",
          raw_text: "more content",
          text_hash: Digest::SHA256.hexdigest("more content"),
          byte_len: 12
        )
        store.close

        check = described_class.new(db_path, "project")
        result = check.call

        expect(result[:status]).to eq(:warning)
        expect(result[:details][:undistilled_count]).to eq(2)
        expect(result[:warnings].first).to include("2 content items")
        expect(result[:warnings].first).to include("claude-memory init")
      end
    end

    context "after backfill resolves the issue" do
      it "returns ok status" do
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        store.upsert_content_item(
          session_id: "s1",
          source: "test",
          raw_text: "test content",
          text_hash: Digest::SHA256.hexdigest("test content"),
          byte_len: 12
        )
        store.backfill_distillation_metrics!
        store.close

        check = described_class.new(db_path, "project")
        result = check.call

        expect(result[:status]).to eq(:ok)
        expect(result[:details][:undistilled_count]).to eq(0)
      end
    end
  end
end
