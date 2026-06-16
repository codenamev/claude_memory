# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::MCP::Tools, "memory.observations" do
  let(:db_path) { File.join(Dir.tmpdir, "tools_obs_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:tools) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  before do
    store.insert_observation(body: "decided to add episodic layer", kind: "decision", priority: 1,
      scope: "project", source_content_item_id: 7, observed_at: "2026-06-01T00:00:00Z")
    store.insert_observation(body: "prefer do...end blocks", kind: "preference", priority: 2,
      scope: "project", observed_at: "2026-05-01T00:00:00Z")
  end

  it "returns observations newest-first with the documented shape" do
    result = tools.call("memory.observations", {"scope" => "project"})

    expect(result[:observation_count]).to eq(2)
    first = result[:observations].first
    expect(first[:body]).to eq("decided to add episodic layer")
    expect(first[:kind]).to eq("decision")
    expect(first[:priority]).to eq(1)
    expect(first[:source_content_item_id]).to eq(7)
    expect(first).to have_key(:observed_ago)
  end

  it "filters to important-only when requested" do
    result = tools.call("memory.observations", {"important_only" => true})

    expect(result[:observation_count]).to eq(1)
    expect(result[:observations].first[:kind]).to eq("decision")
  end

  it "respects the limit" do
    result = tools.call("memory.observations", {"limit" => 1})
    expect(result[:observations].size).to eq(1)
  end

  it "is registered in the tool definitions as read-only" do
    defn = ClaudeMemory::MCP::ToolDefinitions.all.find { |t| t[:name] == "memory.observations" }
    expect(defn).not_to be_nil
    expect(defn[:annotations]).to eq(ClaudeMemory::MCP::ToolDefinitions::READ_ONLY)
  end
end
