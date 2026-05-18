# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Sweep::Maintenance, "OTel retention" do
  let(:tmpdir) { Dir.mktmpdir("otel_retention_#{Process.pid}") }
  let(:db_path) { File.join(tmpdir, "memory.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:maintenance) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_rf(tmpdir)
  end

  it "deletes otel_metrics rows older than retention but keeps fresh ones" do
    fresh = Time.now.utc.iso8601
    old = (Time.now - 365 * 86_400).utc.iso8601
    store.insert_otel_metric(name: "x", value_type: "int", value_int: 1, recorded_at: fresh)
    store.insert_otel_metric(name: "x", value_type: "int", value_int: 1, recorded_at: old)

    deleted = maintenance.prune_old_otel_metrics
    expect(deleted).to eq(1)
    expect(store.otel_metrics.count).to eq(1)
  end

  it "deletes otel_events rows older than retention" do
    fresh = Time.now.utc.iso8601
    old = (Time.now - 365 * 86_400).utc.iso8601
    store.insert_otel_event(event_name: "user_prompt", occurred_at: fresh)
    store.insert_otel_event(event_name: "user_prompt", occurred_at: old)

    deleted = maintenance.prune_old_otel_events
    expect(deleted).to eq(1)
    expect(store.otel_events.count).to eq(1)
  end

  it "deletes otel_traces rows older than retention" do
    fresh = Time.now.utc.iso8601
    old = (Time.now - 365 * 86_400).utc.iso8601
    store.insert_otel_trace_span(trace_id: "t", span_id: "s1", name: "x", recorded_at: fresh)
    store.insert_otel_trace_span(trace_id: "t", span_id: "s2", name: "x", recorded_at: old)

    deleted = maintenance.prune_old_otel_traces
    expect(deleted).to eq(1)
    expect(store.otel_traces.count).to eq(1)
  end
end
