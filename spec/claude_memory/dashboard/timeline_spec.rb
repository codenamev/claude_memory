# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe ClaudeMemory::Dashboard::Timeline do
  let(:tmpdir) { Dir.mktmpdir("dashboard_timeline_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", "memory.sqlite3") }
  let(:manager) do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end
  let(:timeline) { described_class.new(manager) }
  let(:project_store) { manager.project_store }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  describe "#days" do
    it "returns the empty shape when no project store is available" do
      empty_manager = instance_double(ClaudeMemory::Store::StoreManager,
        default_store: nil)
      expect(described_class.new(empty_manager).days).to eq(days: [])
    end

    it "returns an empty days array when nothing falls inside the lookback window" do
      expect(timeline.days).to eq(days: [])
    end

    it "buckets fact creations into per-day entries" do
      entity_id = project_store.find_or_create_entity(type: "repo", name: "app")
      project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "use tabs", status: "active", scope: "project"
      )

      result = timeline.days
      expect(result[:days]).not_to be_empty
      today = Time.now.utc.strftime("%Y-%m-%d")
      today_bucket = result[:days].find { |d| d[:date] == today }
      expect(today_bucket).not_to be_nil
      expect(today_bucket[:facts_created]).to eq(1)
    end

    it "counts content ingestion separately from facts" do
      text = "Some content"
      project_store.upsert_content_item(
        source: "claude_code",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize, raw_text: text
      )

      result = timeline.days
      today = Time.now.utc.strftime("%Y-%m-%d")
      today_bucket = result[:days].find { |d| d[:date] == today }
      expect(today_bucket[:content_ingested]).to eq(1)
      expect(today_bucket[:facts_created]).to eq(0)
    end

    it "splits hook_events from recalls when activity_events exist" do
      ClaudeMemory::ActivityLog.record(project_store,
        event_type: "recall", status: "success",
        details: {tool: "memory.recall", result_count: 1})
      ClaudeMemory::ActivityLog.record(project_store,
        event_type: "hook_ingest", status: "success",
        details: {bytes_read: 100})

      result = timeline.days
      today = Time.now.utc.strftime("%Y-%m-%d")
      today_bucket = result[:days].find { |d| d[:date] == today }
      expect(today_bucket[:hook_events]).to eq(2)
      expect(today_bucket[:recalls]).to eq(1)
    end

    it "ignores events outside the 30-day lookback window" do
      old_iso = (Time.now.utc - 40 * 86_400).iso8601
      project_store.activity_events.insert(
        event_type: "recall", status: "success",
        detail_json: {tool: "memory.recall"}.to_json,
        occurred_at: old_iso
      )

      result = timeline.days
      expect(result[:days].any? { |d| d[:hook_events].positive? }).to be false
    end
  end
end
