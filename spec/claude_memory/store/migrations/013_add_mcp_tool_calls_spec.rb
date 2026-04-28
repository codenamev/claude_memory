# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 013: Add MCP Tool Calls" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    Sequel::Migrator.run(db, migrations_path, target: 12)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "creates the mcp_tool_calls table with the expected columns" do
    Sequel::Migrator.run(db, migrations_path, target: 13)

    expect(db.tables).to include(:mcp_tool_calls)
    columns = db.schema(:mcp_tool_calls).map(&:first)
    expect(columns).to include(:id, :tool_name, :called_at, :duration_ms, :result_count, :scope, :error_class)
  end

  it "creates indexes on tool_name+called_at and called_at" do
    Sequel::Migrator.run(db, migrations_path, target: 13)

    indexes = db["SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='mcp_tool_calls'"].all.map { |r| r[:name] }
    expect(indexes).to include("idx_mcp_tool_calls_name_time", "idx_mcp_tool_calls_called_at")
  end

  it "accepts telemetry rows after migration" do
    Sequel::Migrator.run(db, migrations_path, target: 13)

    now = Time.now.utc.iso8601
    id = db[:mcp_tool_calls].insert(
      tool_name: "memory.recall",
      called_at: now,
      duration_ms: 42,
      result_count: 5,
      scope: "project"
    )
    row = db[:mcp_tool_calls].where(id: id).first
    expect(row[:tool_name]).to eq("memory.recall")
    expect(row[:duration_ms]).to eq(42)
  end

  it "drops the table on down migration" do
    Sequel::Migrator.run(db, migrations_path, target: 13)
    expect(db.tables).to include(:mcp_tool_calls)

    Sequel::Migrator.run(db, migrations_path, target: 12)
    expect(db.tables).not_to include(:mcp_tool_calls)
  end
end
