# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::OTel::PromptScope do
  let(:tmpdir) { Dir.mktmpdir("prompt_scope_#{Process.pid}") }
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
  let(:scope) { described_class.new(manager) }
  let(:project) { manager.project_store }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def at(seconds_ago) = (Time.now - seconds_ago).utc.iso8601

  def insert_activity(event_type:, session_id:, occurred_at:)
    project.activity_events.insert(
      event_type: event_type, status: "success",
      session_id: session_id, detail_json: "{}", occurred_at: occurred_at
    )
  end

  it "tags activity_events sharing the OTel session_id within the prompt window" do
    sid = "session-A"
    pid = "prompt-1"
    row_id = insert_activity(event_type: "hook_ingest", session_id: sid, occurred_at: at(20))
    events = [{event_name: "user_prompt", session_id: sid, prompt_id: pid, occurred_at: at(30)},
      {event_name: "api_request", session_id: sid, prompt_id: pid, occurred_at: at(10)}]

    result = scope.tag(events)
    expect(result[:tagged]).to be >= 1
    expect(project.activity_events.where(id: row_id).get(:prompt_id)).to eq(pid)
  end

  it "tags NULL-session activity_events by time-window match (MCP recall path)" do
    pid = "prompt-1"
    row_id = insert_activity(event_type: "recall", session_id: nil, occurred_at: at(15))
    events = [{event_name: "user_prompt", session_id: "session-A", prompt_id: pid, occurred_at: at(20)},
      {event_name: "tool_result", session_id: "session-A", prompt_id: pid, occurred_at: at(5)}]

    scope.tag(events)
    expect(project.activity_events.where(id: row_id).get(:prompt_id)).to eq(pid)
  end

  it "does not overwrite an already-tagged prompt_id" do
    sid = "session-A"
    project.activity_events.insert(
      event_type: "hook_ingest", status: "success", session_id: sid,
      prompt_id: "earlier-prompt", detail_json: "{}", occurred_at: at(20)
    )
    events = [{event_name: "user_prompt", session_id: sid, prompt_id: "new-prompt", occurred_at: at(30)}]

    scope.tag(events)
    expect(project.activity_events.where(session_id: sid).get(:prompt_id)).to eq("earlier-prompt")
  end

  it "leaves rows outside the prompt window untouched" do
    sid = "session-A"
    far_past = insert_activity(event_type: "hook_ingest", session_id: sid, occurred_at: at(3600))
    events = [{event_name: "user_prompt", session_id: sid, prompt_id: "p", occurred_at: at(30)}]

    scope.tag(events)
    expect(project.activity_events.where(id: far_past).get(:prompt_id)).to be_nil
  end

  it "is idempotent" do
    sid = "session-A"
    pid = "prompt-1"
    insert_activity(event_type: "hook_ingest", session_id: sid, occurred_at: at(20))
    events = [{event_name: "user_prompt", session_id: sid, prompt_id: pid, occurred_at: at(30)}]

    first = scope.tag(events)
    second = scope.tag(events)
    expect(first[:tagged]).to eq(1)
    expect(second[:tagged]).to eq(0)
  end

  it "returns zero-tagged when given no events with prompt_id" do
    expect(scope.tag([])).to eq(tagged: 0, groups: 0)
    expect(scope.tag([{event_name: "x", session_id: "s", prompt_id: nil, occurred_at: at(10)}]))
      .to eq(tagged: 0, groups: 0)
  end

  it "caps the prompt window to MAX_WINDOW_SECONDS to avoid sweeping later prompts" do
    sid = "session-A"
    too_late = insert_activity(
      event_type: "hook_ingest", session_id: sid,
      occurred_at: at(-ClaudeMemory::OTel::PromptScope::MAX_WINDOW_SECONDS - 60)
    )
    events = [{event_name: "user_prompt", session_id: sid, prompt_id: "p", occurred_at: at(20)}]

    scope.tag(events)
    expect(project.activity_events.where(id: too_late).get(:prompt_id)).to be_nil
  end
end
