# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe ClaudeMemory::Commands::StatsCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_db_path) { File.join(tmpdir, ".claude", "memory.sqlite3") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }

  before do
    FileUtils.mkdir_p(File.dirname(project_db_path))
    config = instance_double(
      ClaudeMemory::Configuration,
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_dir: tmpdir,
      claude_config_dir: File.join(tmpdir, ".claude")
    )
    allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)
  end

  after do
    FileUtils.remove_entry(tmpdir)
  end

  def seed_mcp_tool_calls(rows)
    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    rows.each { |row| store.insert_mcp_tool_call(**row) }
    store.close
  end

  describe "--tools" do
    it "reports 'no telemetry recorded' when table is empty" do
      seed_mcp_tool_calls([])
      exit_code = command.call(["--tools"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to match(/No tool calls recorded/)
    end

    it "reports 'database does not exist' when project DB missing" do
      exit_code = command.call(["--tools"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("does not exist")
    end

    it "renders per-tool totals, averages, and error rate" do
      seed_mcp_tool_calls([
        {tool_name: "memory.recall", duration_ms: 10, result_count: 3},
        {tool_name: "memory.recall", duration_ms: 20, result_count: 5},
        {tool_name: "memory.recall", duration_ms: 30, result_count: 0, error_class: "ArgumentError"},
        {tool_name: "memory.conflicts", duration_ms: 5, result_count: 1}
      ])

      exit_code = command.call(["--tools"])
      expect(exit_code).to eq(0)

      out = stdout.string
      expect(out).to include("Total calls: 4")
      expect(out).to include("Errors: 1")
      expect(out).to include("memory.recall")
      expect(out).to include("memory.conflicts")
      # memory.recall: avg = (10+20+30)/3 = 20.0
      expect(out).to match(/memory\.recall\s+3\s+20\.0/)
    end

    it "filters by --since days" do
      old = (Time.now - 30 * 86400).utc.iso8601
      recent = (Time.now - 1 * 86400).utc.iso8601
      seed_mcp_tool_calls([
        {tool_name: "memory.recall", duration_ms: 10, result_count: 1, called_at: old},
        {tool_name: "memory.recall", duration_ms: 20, result_count: 2, called_at: recent}
      ])

      command.call(["--tools", "--since", "7"])
      expect(stdout.string).to include("Total calls: 1")
      expect(stdout.string).to include("last 7 days")
    end
  end

  describe "--stale" do
    def seed_stale_fact(scope:, days_ago:)
      store_path = (scope == "project") ? project_db_path : global_db_path
      store = ClaudeMemory::Store::SQLiteStore.new(store_path)
      entity = store.find_or_create_entity(type: "repo", name: "app")
      fact_id = store.insert_fact(
        subject_entity_id: entity, predicate: "convention", object_literal: "old thing-#{rand(1_000_000)}",
        status: "active", scope: scope, confidence: 0.9
      )
      ts = (Time.now.utc - days_ago * 86_400).iso8601
      store.facts.where(id: fact_id).update(created_at: ts, last_recalled_at: ts)
      store.close
      fact_id
    end

    it "reports zero when nothing is stale" do
      ClaudeMemory::Store::SQLiteStore.new(project_db_path).close

      exit_code = command.call(["--stale", "--stale-days", "14"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("No stale facts.")
    end

    it "lists stale facts with their last_recalled_at" do
      seed_stale_fact(scope: "project", days_ago: 30)

      command.call(["--stale", "--stale-days", "14"])

      expect(stdout.string).to include("Stale facts (last_recalled_at older than 14 days)")
      expect(stdout.string).to include("Total: 1")
      expect(stdout.string).to include("convention")
    end

    it "respects an explicit --stale-days override" do
      seed_stale_fact(scope: "project", days_ago: 20)

      command.call(["--stale", "--stale-days", "30"])

      expect(stdout.string).to include("No stale facts.")
    end
  end
end
