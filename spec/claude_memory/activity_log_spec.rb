# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::ActivityLog do
  let(:db_path) { File.join(Dir.tmpdir, "activity_log_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe ".record" do
    it "inserts an activity event" do
      described_class.record(store,
        event_type: "hook_ingest",
        status: "success",
        session_id: "sess-123",
        duration_ms: 42,
        details: {bytes_read: 1024})

      events = store.activity_events.all
      expect(events.size).to eq(1)

      event = events.first
      expect(event[:event_type]).to eq("hook_ingest")
      expect(event[:status]).to eq("success")
      expect(event[:session_id]).to eq("sess-123")
      expect(event[:duration_ms]).to eq(42)
      expect(event[:occurred_at]).not_to be_nil
    end

    it "stores details as JSON" do
      described_class.record(store,
        event_type: "recall",
        status: "success",
        details: {query: "test query", result_count: 5})

      event = store.activity_events.first
      parsed = JSON.parse(event[:detail_json], symbolize_names: true)
      expect(parsed[:query]).to eq("test query")
      expect(parsed[:result_count]).to eq(5)
    end

    it "handles nil details gracefully" do
      described_class.record(store,
        event_type: "hook_sweep",
        status: "success")

      event = store.activity_events.first
      expect(event[:detail_json]).to be_nil
    end

    it "does not raise on errors" do
      # Close the store to force an error
      store.close

      expect {
        described_class.record(store,
          event_type: "test",
          status: "success")
      }.not_to raise_error
    end
  end

  describe ".recent" do
    before do
      3.times do |i|
        described_class.record(store,
          event_type: (i < 2) ? "hook_ingest" : "recall",
          status: "success",
          details: {index: i})
      end
    end

    it "returns events ordered by most recent first" do
      events = described_class.recent(store)
      expect(events.size).to eq(3)
      # Parsed details should be available
      expect(events.first[:details]).to be_a(Hash)
    end

    it "filters by event_type" do
      events = described_class.recent(store, event_type: "recall")
      expect(events.size).to eq(1)
    end

    it "respects limit" do
      events = described_class.recent(store, limit: 2)
      expect(events.size).to eq(2)
    end

    it "filters by since timestamp" do
      future = (Time.now + 3600).utc.iso8601
      events = described_class.recent(store, since: future)
      expect(events).to be_empty
    end
  end

  describe ".summary" do
    before do
      described_class.record(store, event_type: "hook_ingest", status: "success")
      described_class.record(store, event_type: "hook_ingest", status: "success")
      described_class.record(store, event_type: "hook_ingest", status: "skipped")
      described_class.record(store, event_type: "recall", status: "success")
    end

    it "returns counts grouped by event_type and status" do
      result = described_class.summary(store)

      expect(result["hook_ingest"][:success]).to eq(2)
      expect(result["hook_ingest"][:skipped]).to eq(1)
      expect(result["recall"][:success]).to eq(1)
    end
  end
end
