# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 015: Add Activity Events" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    Sequel::Migrator.run(db, migrations_path, target: 14)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "creates the activity_events table with the expected columns" do
    Sequel::Migrator.run(db, migrations_path, target: 15)

    expect(db.tables).to include(:activity_events)
    columns = db.schema(:activity_events).map(&:first)
    expect(columns).to include(:id, :event_type, :session_id, :status, :duration_ms, :detail_json, :occurred_at)
  end

  it "creates indexes on event_type, occurred_at, and session_id" do
    Sequel::Migrator.run(db, migrations_path, target: 15)

    indexes = db["SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='activity_events'"].all.map { |r| r[:name] }
    expect(indexes).to include("idx_activity_events_type", "idx_activity_events_occurred_at", "idx_activity_events_session")
  end

  it "enforces NOT NULL on event_type, status, occurred_at" do
    Sequel::Migrator.run(db, migrations_path, target: 15)

    expect {
      db[:activity_events].insert(status: "success", occurred_at: Time.now.utc.iso8601)
    }.to raise_error(Sequel::DatabaseError, /event_type/i)

    expect {
      db[:activity_events].insert(event_type: "recall", occurred_at: Time.now.utc.iso8601)
    }.to raise_error(Sequel::DatabaseError, /status/i)

    expect {
      db[:activity_events].insert(event_type: "recall", status: "success")
    }.to raise_error(Sequel::DatabaseError, /occurred_at/i)
  end

  it "accepts a fully-formed activity event" do
    Sequel::Migrator.run(db, migrations_path, target: 15)

    now = Time.now.utc.iso8601
    id = db[:activity_events].insert(
      event_type: "recall",
      session_id: "abc123",
      status: "success",
      duration_ms: 17,
      detail_json: '{"result_count":3}',
      occurred_at: now
    )
    row = db[:activity_events].where(id: id).first
    expect(row[:event_type]).to eq("recall")
    expect(row[:session_id]).to eq("abc123")
    expect(row[:detail_json]).to eq('{"result_count":3}')
  end

  it "drops the table on down migration" do
    Sequel::Migrator.run(db, migrations_path, target: 15)
    expect(db.tables).to include(:activity_events)

    Sequel::Migrator.run(db, migrations_path, target: 14)
    expect(db.tables).not_to include(:activity_events)
  end
end
