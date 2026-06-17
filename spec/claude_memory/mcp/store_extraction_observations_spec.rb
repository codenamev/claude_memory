# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::MCP::Tools, "store_extraction observations (Layer-2 observer)" do
  let(:db_path) { File.join(Dir.tmpdir, "store_obs_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:tools) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  it "persists Claude-supplied observations and reports the count" do
    result = tools.call("memory.store_extraction", {
      "scope" => "project", "facts" => [],
      "observations" => [
        {"body" => "decided to use SQLite because it is embedded", "kind" => "decision", "priority" => 1},
        {"body" => "prefers small PRs", "kind" => "preference", "priority" => 2}
      ]
    })

    expect(result[:observations_created]).to eq(2)
    bodies = store.recent_observations(limit: 10).map { |o| o[:body] }
    expect(bodies).to contain_exactly("decided to use SQLite because it is embedded", "prefers small PRs")
  end

  describe "border coercion of semi-trusted input" do
    it "skips an observation with a blank body" do
      result = tools.call("memory.store_extraction", {
        "facts" => [], "observations" => [{"body" => "   ", "kind" => "event"}]
      })
      expect(result[:observations_created]).to eq(0)
    end

    it "defaults an unknown kind to 'event'" do
      tools.call("memory.store_extraction", {"facts" => [], "observations" => [{"body" => "x happened", "kind" => "bogus"}]})
      expect(store.recent_observations.first[:kind]).to eq("event")
    end

    it "clamps an out-of-range priority to info" do
      tools.call("memory.store_extraction", {"facts" => [], "observations" => [{"body" => "noise", "priority" => 99}]})
      expect(store.recent_observations.first[:priority]).to eq(ClaudeMemory::Domain::Observation::INFO)
    end
  end

  it "does not disturb fact extraction when observations are present" do
    result = tools.call("memory.store_extraction", {
      "facts" => [{"subject" => "repo", "predicate" => "uses_database", "object" => "sqlite"}],
      "observations" => [{"body" => "noted the db choice", "kind" => "event"}]
    })

    expect(result[:facts_created]).to eq(1)
    expect(result[:observations_created]).to eq(1)
  end

  it "reports zero observations_created when none are supplied (consistent shape)" do
    result = tools.call("memory.store_extraction", {"facts" => []})
    expect(result[:observations_created]).to eq(0)
  end
end
