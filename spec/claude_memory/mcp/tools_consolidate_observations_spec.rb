# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::MCP::Tools, "memory.consolidate_observations" do
  let(:db_path) { File.join(Dir.tmpdir, "tools_consolidate_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:tools) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def three_related
    [
      store.insert_observation(body: "decided to use Postgres", kind: "decision", priority: 1),
      store.insert_observation(body: "chose Postgres for JSONB", kind: "decision", priority: 1),
      store.insert_observation(body: "going with Postgres for constraints", kind: "decision", priority: 2)
    ]
  end

  it "merges related observations, summing corroboration and tombstoning the sources" do
    a, b, c = three_related

    result = tools.call("memory.consolidate_observations", {
      "from_ids" => [a, b, c], "kind" => "decision", "priority" => 1,
      "body" => "decided to use Postgres because of JSONB and strong constraints"
    })

    expect(result[:success]).to be true
    expect(result[:merged]).to eq(3)
    expect(result[:corroboration_count]).to eq(3)

    merged = store.observations.where(id: result[:consolidated_into]).first
    expect(merged[:corroboration_count]).to eq(3)
    expect(store.recent_observations.map { |o| o[:id] }).to eq([result[:consolidated_into]])
    [a, b, c].each do |id|
      row = store.observations.where(id: id).first
      expect(row[:status]).to eq("consolidated")
      expect(row[:consolidated_into]).to eq(result[:consolidated_into])
    end
  end

  it "lets the merged observation cross the promotion gate via combined corroboration" do
    a, b, c = three_related
    expect(store.promotion_candidates(min_corroboration: 2)).to be_empty

    tools.call("memory.consolidate_observations", {"from_ids" => [a, b, c], "body" => "use Postgres because JSONB"})

    expect(store.promotion_candidates(min_corroboration: 2).size).to eq(1)
  end

  it "refuses fewer than two ids" do
    a = store.insert_observation(body: "lonely", kind: "decision", priority: 1)
    expect(tools.call("memory.consolidate_observations", {"from_ids" => [a], "body" => "x"})[:error]).to match(/at least 2/i)
  end

  it "requires a synthesized body" do
    a, b, = three_related
    expect(tools.call("memory.consolidate_observations", {"from_ids" => [a, b], "body" => "  "})[:error]).to match(/body is required/i)
  end

  it "returns an error when fewer than two of the ids are active in scope" do
    a = store.insert_observation(body: "one", kind: "decision", priority: 1)
    gone = store.insert_observation(body: "two", kind: "decision", priority: 1)
    store.tombstone_observation(gone, into_id: a)

    result = tools.call("memory.consolidate_observations", {"from_ids" => [a, gone], "body" => "merged"})
    expect(result[:error]).to match(/at least 2 active/i)
  end

  it "is registered as a write tool" do
    defn = ClaudeMemory::MCP::ToolDefinitions.all.find { |t| t[:name] == "memory.consolidate_observations" }
    expect(defn[:annotations]).to eq(ClaudeMemory::MCP::ToolDefinitions::WRITE)
  end
end
