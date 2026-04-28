# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 016: Add Moment Feedback" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    Sequel::Migrator.run(db, migrations_path, target: 15)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  def seed_event!
    db[:activity_events].insert(
      event_type: "recall",
      status: "success",
      occurred_at: Time.now.utc.iso8601
    )
  end

  it "creates the moment_feedback table with the expected columns" do
    Sequel::Migrator.run(db, migrations_path, target: 16)

    expect(db.tables).to include(:moment_feedback)
    columns = db.schema(:moment_feedback).map(&:first)
    expect(columns).to include(:id, :event_id, :verdict, :note, :recorded_at)
  end

  it "enforces a unique index on event_id so one moment has one verdict" do
    Sequel::Migrator.run(db, migrations_path, target: 16)
    event_id = seed_event!
    now = Time.now.utc.iso8601

    db[:moment_feedback].insert(event_id: event_id, verdict: "up", recorded_at: now)
    expect {
      db[:moment_feedback].insert(event_id: event_id, verdict: "down", recorded_at: now)
    }.to raise_error(Sequel::UniqueConstraintViolation)
  end

  it "allows different events to each have their own verdict" do
    Sequel::Migrator.run(db, migrations_path, target: 16)
    event_a = seed_event!
    event_b = seed_event!
    now = Time.now.utc.iso8601

    db[:moment_feedback].insert(event_id: event_a, verdict: "up", recorded_at: now)
    db[:moment_feedback].insert(event_id: event_b, verdict: "down", recorded_at: now)
    expect(db[:moment_feedback].count).to eq(2)
  end

  it "enforces NOT NULL on event_id, verdict, recorded_at" do
    Sequel::Migrator.run(db, migrations_path, target: 16)

    now = Time.now.utc.iso8601
    expect {
      db[:moment_feedback].insert(verdict: "up", recorded_at: now)
    }.to raise_error(Sequel::DatabaseError, /event_id/i)
    expect {
      db[:moment_feedback].insert(event_id: 1, recorded_at: now)
    }.to raise_error(Sequel::DatabaseError, /verdict/i)
    expect {
      db[:moment_feedback].insert(event_id: 1, verdict: "up")
    }.to raise_error(Sequel::DatabaseError, /recorded_at/i)
  end

  it "drops the table on down migration" do
    Sequel::Migrator.run(db, migrations_path, target: 16)
    expect(db.tables).to include(:moment_feedback)

    Sequel::Migrator.run(db, migrations_path, target: 15)
    expect(db.tables).not_to include(:moment_feedback)
  end
end
