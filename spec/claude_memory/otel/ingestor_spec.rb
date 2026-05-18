# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::OTel::Ingestor do
  let(:tmpdir) { Dir.mktmpdir("otel_ingestor_#{Process.pid}") }
  let(:db_path) { File.join(tmpdir, "memory.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:ingestor) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_rf(tmpdir)
  end

  it "persists metric rows and reports inserted counts" do
    rows = [
      {name: "claude_code.token.usage", value_type: "int", value_int: 100, value_float: nil,
       unit: "tokens", attributes: {"type" => "input"}, resource: {"service.name" => "claude-code"},
       recorded_at: "2026-05-05T10:00:00Z"}
    ]
    result = ingestor.ingest(metrics: rows)
    expect(result).to be_success
    expect(result.value[:metrics]).to eq(1)
    expect(store.otel_metrics.count).to eq(1)
    expect(store.otel_metrics.first[:value_int]).to eq(100)
  end

  it "persists event rows" do
    rows = [
      {event_name: "user_prompt", occurred_at: "2026-05-05T10:00:00Z",
       session_id: "s-1", prompt_id: "p-1",
       attributes: {"event.name" => "user_prompt"}, resource: {}}
    ]
    result = ingestor.ingest(events: rows)
    expect(result).to be_success
    expect(store.otel_events.count).to eq(1)
    expect(store.otel_events.first[:prompt_id]).to eq("p-1")
  end

  it "rolls back the entire batch when one insert fails" do
    valid_row = {name: "claude_code.token.usage", value_type: "int", value_int: 1, value_float: nil,
                 unit: "tokens", attributes: {}, resource: {},
                 recorded_at: "2026-05-05T10:00:00Z"}
    # Missing required :name violates NOT NULL
    bad_row = {name: nil, value_type: "int", value_int: 1, value_float: nil, unit: nil,
               attributes: {}, resource: {}, recorded_at: "2026-05-05T10:00:01Z"}

    result = ingestor.ingest(metrics: [valid_row, bad_row])
    expect(result).to be_failure
    expect(store.otel_metrics.count).to eq(0)
  end

  it "fails gracefully on non-Hash input" do
    expect(ingestor.ingest(nil)).to be_failure
  end

  it "treats a missing key as zero rows for that kind" do
    result = ingestor.ingest(metrics: [])
    expect(result).to be_success
    expect(result.value).to eq(metrics: 0, events: 0, traces: 0)
  end
end
