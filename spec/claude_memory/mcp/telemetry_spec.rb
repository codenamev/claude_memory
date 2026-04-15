# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::MCP::Telemetry do
  let(:db_path) { File.join(Dir.tmpdir, "telemetry_test_#{Process.pid}_#{rand(1000)}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:telemetry) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#record" do
    it "writes a row on success and returns the block result" do
      result = telemetry.record("memory.recall", {"query" => "ruby", "scope" => "project"}) do
        {facts: [{id: 1}, {id: 2}, {id: 3}]}
      end

      expect(result).to eq({facts: [{id: 1}, {id: 2}, {id: 3}]})

      rows = store.mcp_tool_calls.all
      expect(rows.size).to eq(1)
      row = rows.first
      expect(row[:tool_name]).to eq("memory.recall")
      expect(row[:result_count]).to eq(3)
      expect(row[:scope]).to eq("project")
      expect(row[:error_class]).to be_nil
      expect(row[:duration_ms]).to be >= 0
    end

    it "records and re-raises when the block raises" do
      expect {
        telemetry.record("memory.recall", {}) { raise ArgumentError, "boom" }
      }.to raise_error(ArgumentError, "boom")

      row = store.mcp_tool_calls.first
      expect(row[:tool_name]).to eq("memory.recall")
      expect(row[:error_class]).to eq("ArgumentError")
      expect(row[:result_count]).to be_nil
    end

    it "extracts result counts from common response shapes" do
      telemetry.record("memory.conflicts", {}) { {conflicts: [1, 2]} }
      telemetry.record("memory.changes", {}) { {changes: [1]} }
      telemetry.record("memory.recall_index", {}) { {results: [1, 2, 3, 4]} }

      counts = store.mcp_tool_calls.select_map(:result_count)
      expect(counts).to contain_exactly(2, 1, 4)
    end

    it "leaves result_count nil for unrecognized shapes" do
      telemetry.record("memory.stats", {}) { {some_metric: 42} }

      expect(store.mcp_tool_calls.first[:result_count]).to be_nil
    end

    it "swallows database errors so tool calls never fail on telemetry" do
      allow(store).to receive(:insert_mcp_tool_call)
        .and_raise(Sequel::DatabaseError, "disk full")

      expect {
        telemetry.record("memory.recall", {}) { {facts: []} }
      }.not_to raise_error
    end
  end
end
