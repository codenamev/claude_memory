# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe ClaudeMemory::Commands::OtelCommand, "#backfill" do
  let(:tmpdir) { Dir.mktmpdir("otel_backfill_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, ".claude", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", ".claude", "memory.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_wrap_original do |orig, **kwargs|
      orig.call(global_db_path: global_db_path, project_db_path: project_db_path,
        project_path: File.dirname(project_db_path, 2), **kwargs)
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  def at(seconds_ago) = (Time.now - seconds_ago).utc.iso8601

  it "exits cleanly when no otel_events exist" do
    # Initialize stores so the global DB exists with the schema applied.
    mgr = ClaudeMemory::Store::StoreManager.new
    mgr.ensure_both!
    mgr.close

    expect(command.call(["--backfill"])).to eq(0)
    expect(stdout.string).to include("No OTel events with prompt_id")
  end

  it "tags historical activity_events from prior otel_events" do
    mgr = ClaudeMemory::Store::StoreManager.new
    mgr.ensure_both!
    sid = "session-X"
    pid = "prompt-X"

    project_event_id = mgr.project_store.activity_events.insert(
      event_type: "hook_ingest", status: "success",
      session_id: sid, detail_json: "{}", occurred_at: at(20)
    )
    mgr.global_store.insert_otel_event(
      event_name: "user_prompt", occurred_at: at(30),
      session_id: sid, prompt_id: pid, attributes: {}
    )
    mgr.close

    expect(command.call(["--backfill"])).to eq(0)
    expect(stdout.string).to match(/tagged 1 activity_event/)

    mgr2 = ClaudeMemory::Store::StoreManager.new
    mgr2.ensure_project!
    expect(mgr2.project_store.activity_events.where(id: project_event_id).get(:prompt_id)).to eq(pid)
    mgr2.close
  end

  it "is idempotent — a second run tags zero additional rows" do
    mgr = ClaudeMemory::Store::StoreManager.new
    mgr.ensure_both!
    sid = "session-Y"
    pid = "prompt-Y"
    mgr.project_store.activity_events.insert(
      event_type: "hook_ingest", status: "success",
      session_id: sid, detail_json: "{}", occurred_at: at(20)
    )
    mgr.global_store.insert_otel_event(
      event_name: "user_prompt", occurred_at: at(30),
      session_id: sid, prompt_id: pid, attributes: {}
    )
    mgr.close

    command.call(["--backfill"])
    stdout.truncate(0)
    stdout.rewind

    expect(command.call(["--backfill"])).to eq(0)
    expect(stdout.string).to match(/tagged 0 activity_event/)
  end
end
