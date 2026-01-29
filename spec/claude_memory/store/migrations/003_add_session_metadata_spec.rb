# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 003: Add Session Metadata" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 002 first
    Sequel::Migrator.run(db, migrations_path, target: 2)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    content_items_columns = db.schema(:content_items).map(&:first)
    expect(content_items_columns).to include(
      :git_branch,
      :cwd,
      :claude_version,
      :thinking_level
    )

    expect(db.tables).to include(:tool_calls)
  end

  it "creates tool_calls table with correct columns" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    tool_calls_columns = db.schema(:tool_calls).map(&:first)
    expect(tool_calls_columns).to include(
      :id,
      :content_item_id,
      :tool_name,
      :tool_input,
      :tool_result,
      :is_error,
      :timestamp
    )
  end

  it "creates git_branch index on content_items" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    indexes = db.indexes(:content_items)
    expect(indexes.keys).to include(:idx_content_items_git_branch)
  end

  it "creates tool_calls indexes" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    indexes = db.indexes(:tool_calls)
    expect(indexes.keys).to include(
      :idx_tool_calls_tool_name,
      :idx_tool_calls_content_item
    )
  end

  it "allows storing and querying session metadata" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    content_item_id = db[:content_items].insert(
      source: "test",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 100,
      git_branch: "feature/test",
      cwd: "/Users/test/project",
      claude_version: "4.5",
      thinking_level: "high"
    )

    content = db[:content_items].where(id: content_item_id).first
    expect(content[:git_branch]).to eq("feature/test")
    expect(content[:cwd]).to eq("/Users/test/project")
    expect(content[:claude_version]).to eq("4.5")
    expect(content[:thinking_level]).to eq("high")
  end

  it "allows tracking tool calls with foreign key constraint" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    content_item_id = db[:content_items].insert(
      source: "test",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 100
    )

    tool_call_id = db[:tool_calls].insert(
      content_item_id: content_item_id,
      tool_name: "Read",
      tool_input: '{"file": "test.rb"}',
      tool_result: "file contents...",
      is_error: false,
      timestamp: Time.now.utc.iso8601
    )

    tool_call = db[:tool_calls].where(id: tool_call_id).first
    expect(tool_call[:tool_name]).to eq("Read")
    expect(tool_call[:tool_input]).to eq('{"file": "test.rb"}')
    expect(tool_call[:is_error]).to eq(0) # SQLite stores booleans as 0/1
  end

  it "cascades delete when content_item is removed" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    content_item_id = db[:content_items].insert(
      source: "test",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 100
    )

    db[:tool_calls].insert(
      content_item_id: content_item_id,
      tool_name: "Read",
      timestamp: Time.now.utc.iso8601
    )

    expect(db[:tool_calls].count).to eq(1)

    db[:content_items].where(id: content_item_id).delete
    expect(db[:tool_calls].count).to eq(0)
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 3)

    expect(db.tables).to include(:tool_calls)
    expect(db.schema(:content_items).map(&:first)).to include(:git_branch)

    Sequel::Migrator.run(db, migrations_path, target: 2)

    expect(db.tables).not_to include(:tool_calls)
    expect(db.schema(:content_items).map(&:first)).not_to include(
      :git_branch,
      :cwd,
      :claude_version,
      :thinking_level
    )
  end
end
