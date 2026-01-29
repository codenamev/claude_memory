# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 005: Add Incremental Sync" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 004 first
    Sequel::Migrator.run(db, migrations_path, target: 4)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 5)

    content_items_columns = db.schema(:content_items).map(&:first)
    expect(content_items_columns).to include(:source_mtime)
  end

  it "creates source_mtime index on content_items" do
    Sequel::Migrator.run(db, migrations_path, target: 5)

    indexes = db.indexes(:content_items)
    expect(indexes.keys).to include(:idx_content_items_source_mtime)
  end

  it "allows storing and querying source_mtime" do
    Sequel::Migrator.run(db, migrations_path, target: 5)

    mtime_old = "2026-01-01T12:00:00Z"
    mtime_new = "2026-01-27T15:30:00Z"

    old_content_id = db[:content_items].insert(
      source: "transcript_old.jsonl",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 100,
      source_mtime: mtime_old
    )

    new_content_id = db[:content_items].insert(
      source: "transcript_new.jsonl",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "def456",
      byte_len: 200,
      source_mtime: mtime_new
    )

    # Query by mtime
    old_content = db[:content_items].where(source_mtime: mtime_old).first
    expect(old_content[:id]).to eq(old_content_id)

    new_content = db[:content_items].where(source_mtime: mtime_new).first
    expect(new_content[:id]).to eq(new_content_id)
  end

  it "allows null source_mtime for content without file source" do
    Sequel::Migrator.run(db, migrations_path, target: 5)

    content_id = db[:content_items].insert(
      source: "manual_entry",
      ingested_at: Time.now.utc.iso8601,
      text_hash: "abc123",
      byte_len: 100
    )

    content = db[:content_items].where(id: content_id).first
    expect(content[:source_mtime]).to be_nil
  end

  it "can efficiently find stale content by mtime comparison" do
    Sequel::Migrator.run(db, migrations_path, target: 5)

    # Insert old content
    db[:content_items].insert(
      source: "transcript.jsonl",
      session_id: "session-1",
      ingested_at: "2026-01-01T12:00:00Z",
      text_hash: "old_hash",
      byte_len: 100,
      source_mtime: "2026-01-01T11:00:00Z"
    )

    # Insert newer content
    db[:content_items].insert(
      source: "transcript.jsonl",
      session_id: "session-2",
      ingested_at: "2026-01-27T12:00:00Z",
      text_hash: "new_hash",
      byte_len: 150,
      source_mtime: "2026-01-27T11:00:00Z"
    )

    # Find all content older than a cutoff
    cutoff = "2026-01-15T00:00:00Z"
    stale_content = db[:content_items].where { source_mtime < cutoff }.all
    expect(stale_content.length).to eq(1)
    expect(stale_content.first[:session_id]).to eq("session-1")
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 5)

    expect(db.schema(:content_items).map(&:first)).to include(:source_mtime)

    Sequel::Migrator.run(db, migrations_path, target: 4)

    expect(db.schema(:content_items).map(&:first)).not_to include(:source_mtime)
  end
end
