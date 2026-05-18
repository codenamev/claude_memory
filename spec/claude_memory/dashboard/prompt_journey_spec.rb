# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Dashboard::PromptJourney do
  let(:tmpdir) { Dir.mktmpdir("prompt_journey_#{Process.pid}") }
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
  let(:panel) { described_class.new(manager) }
  let(:store) { manager.global_store }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  it "returns the empty shape when no rows match the prompt_id" do
    expect(panel.for("missing")).to eq(prompt_id: "missing", event_count: 0, events: [])
  end

  it "merges otel_events and activity_events on prompt_id, sorted by occurred_at" do
    store.insert_otel_event(event_name: "user_prompt", occurred_at: "2026-05-05T10:00:00Z",
      session_id: "s-1", prompt_id: "p-42", attributes: {})
    store.insert_otel_event(event_name: "tool_result", occurred_at: "2026-05-05T10:00:02Z",
      session_id: "s-1", prompt_id: "p-42",
      attributes: {"tool_name" => "Read", "duration_ms" => 12})
    store.activity_events.insert(
      event_type: "recall", status: "success", duration_ms: 5,
      session_id: "s-1", prompt_id: "p-42",
      detail_json: {result_count: 3}.to_json,
      occurred_at: "2026-05-05T10:00:01Z"
    )

    result = panel.for("p-42")
    expect(result[:event_count]).to eq(3)
    names_in_order = result[:events].map { |e| e[:name] }
    expect(names_in_order).to eq(%w[user_prompt recall tool_result])
    expect(result[:events][2][:tool_name]).to eq("Read")
  end
end
