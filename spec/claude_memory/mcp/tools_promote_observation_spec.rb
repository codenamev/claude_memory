# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::MCP::Tools, "memory.promote_observation" do
  let(:db_path) { File.join(Dir.tmpdir, "tools_promote_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:tools) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def corroborated_observation(body: "use SQLite for storage", count: 2)
    cid = store.upsert_content_item(source: "t", text_hash: "h#{rand(1_000_000)}", byte_len: body.bytesize, raw_text: body)
    id = store.insert_observation(body: body, kind: "decision", priority: 1, source_content_item_id: cid)
    store.increment_corroboration(id, by: count - 1)
    id
  end

  it "promotes a corroborated observation into a fact and marks it promoted" do
    id = corroborated_observation

    result = tools.call("memory.promote_observation", {
      "observation_id" => id, "predicate" => "decision",
      "object" => "claude_memory uses SQLite because it is embedded and zero-config"
    })

    expect(result[:success]).to be true
    expect(result[:fact_id]).to be_a(Integer)
    expect(store.facts.where(id: result[:fact_id]).get(:object_literal)).to include("SQLite")
    expect(store.observations.where(id: id).get(:promoted_fact_id)).to eq(result[:fact_id])
    expect(store.promotion_candidates(min_corroboration: 2)).to be_empty
  end

  it "refuses a one-off observation (anti-hallucination gate)" do
    id = store.insert_observation(body: "seen once", kind: "decision", priority: 1) # count 1

    result = tools.call("memory.promote_observation", {
      "observation_id" => id, "predicate" => "decision", "object" => "X because Y"
    })

    expect(result[:error]).to match(/not yet corroborated/i)
    expect(store.observations.where(id: id).get(:promoted_at)).to be_nil
  end

  it "refuses to promote the same observation twice" do
    id = corroborated_observation
    tools.call("memory.promote_observation", {"observation_id" => id, "predicate" => "decision", "object" => "a because b"})

    again = tools.call("memory.promote_observation", {"observation_id" => id, "predicate" => "decision", "object" => "a because b"})
    expect(again[:error]).to match(/already promoted/i)
  end

  it "errors on a missing observation or missing fields" do
    expect(tools.call("memory.promote_observation", {"observation_id" => 9999, "predicate" => "decision", "object" => "z"})[:error]).to match(/not found/i)
    id = corroborated_observation
    expect(tools.call("memory.promote_observation", {"observation_id" => id, "predicate" => "decision", "object" => ""})[:error]).to match(/required/i)
  end

  it "is registered as a write tool in the definitions" do
    defn = ClaudeMemory::MCP::ToolDefinitions.all.find { |t| t[:name] == "memory.promote_observation" }
    expect(defn).not_to be_nil
    expect(defn[:annotations]).to eq(ClaudeMemory::MCP::ToolDefinitions::WRITE)
  end
end
