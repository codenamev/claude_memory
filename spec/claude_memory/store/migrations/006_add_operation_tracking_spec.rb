# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"
require "json"

RSpec.describe "Migration 006: Add Operation Tracking" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.sqlite(db_path) }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 005 first
    Sequel::Migrator.run(db, migrations_path, target: 5)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    expect(db.tables).to include(:operation_progress, :schema_health)
  end

  it "creates operation_progress table with correct columns" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    columns = db.schema(:operation_progress).map(&:first)
    expect(columns).to include(
      :id,
      :operation_type,
      :scope,
      :status,
      :total_items,
      :processed_items,
      :checkpoint_data,
      :started_at,
      :completed_at
    )
  end

  it "creates schema_health table with correct columns" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    columns = db.schema(:schema_health).map(&:first)
    expect(columns).to include(
      :id,
      :checked_at,
      :schema_version,
      :validation_status,
      :issues_json,
      :table_counts_json
    )
  end

  it "creates operation_progress indexes" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    indexes = db.indexes(:operation_progress)
    expect(indexes.keys).to include(
      :idx_operation_progress_type,
      :idx_operation_progress_status
    )
  end

  it "creates schema_health index" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    indexes = db.indexes(:schema_health)
    expect(indexes.keys).to include(:idx_schema_health_checked_at)
  end

  it "allows tracking long-running operations with checkpoints" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    operation_id = db[:operation_progress].insert(
      operation_type: "index_embeddings",
      scope: "global",
      status: "running",
      total_items: 1000,
      processed_items: 250,
      checkpoint_data: JSON.generate({last_fact_id: 42, batch: 3}),
      started_at: Time.now.utc.iso8601
    )

    operation = db[:operation_progress].where(id: operation_id).first
    expect(operation[:operation_type]).to eq("index_embeddings")
    expect(operation[:status]).to eq("running")
    expect(operation[:processed_items]).to eq(250)

    checkpoint = JSON.parse(operation[:checkpoint_data])
    expect(checkpoint["last_fact_id"]).to eq(42)
    expect(checkpoint["batch"]).to eq(3)

    # Update progress
    db[:operation_progress].where(id: operation_id).update(
      processed_items: 500,
      checkpoint_data: JSON.generate({last_fact_id: 85, batch: 6})
    )

    updated = db[:operation_progress].where(id: operation_id).first
    expect(updated[:processed_items]).to eq(500)
  end

  it "allows completing operations" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    operation_id = db[:operation_progress].insert(
      operation_type: "sweep",
      scope: "project",
      status: "running",
      total_items: 100,
      processed_items: 0,
      started_at: Time.now.utc.iso8601
    )

    # Complete the operation
    completed_at = Time.now.utc.iso8601
    db[:operation_progress].where(id: operation_id).update(
      status: "completed",
      processed_items: 100,
      completed_at: completed_at
    )

    operation = db[:operation_progress].where(id: operation_id).first
    expect(operation[:status]).to eq("completed")
    expect(operation[:completed_at]).to eq(completed_at)
  end

  it "allows querying operations by type and status" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    db[:operation_progress].insert(
      operation_type: "distill",
      scope: "global",
      status: "running",
      started_at: Time.now.utc.iso8601
    )

    db[:operation_progress].insert(
      operation_type: "distill",
      scope: "project",
      status: "completed",
      started_at: Time.now.utc.iso8601,
      completed_at: Time.now.utc.iso8601
    )

    db[:operation_progress].insert(
      operation_type: "sweep",
      scope: "global",
      status: "running",
      started_at: Time.now.utc.iso8601
    )

    # Find all running operations
    running = db[:operation_progress].where(status: "running").all
    expect(running.length).to eq(2)

    # Find all distill operations
    distills = db[:operation_progress].where(operation_type: "distill").all
    expect(distills.length).to eq(2)
  end

  it "allows recording schema health checks" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    issues = ["Missing foreign key constraint on facts.subject_entity_id"]
    table_counts = {facts: 42, entities: 15, content_items: 8}

    health_id = db[:schema_health].insert(
      checked_at: Time.now.utc.iso8601,
      schema_version: 6,
      validation_status: "healthy",
      issues_json: JSON.generate(issues),
      table_counts_json: JSON.generate(table_counts)
    )

    health = db[:schema_health].where(id: health_id).first
    expect(health[:validation_status]).to eq("healthy")
    expect(health[:schema_version]).to eq(6)

    parsed_issues = JSON.parse(health[:issues_json])
    expect(parsed_issues).to eq(issues)

    parsed_counts = JSON.parse(health[:table_counts_json])
    expect(parsed_counts["facts"]).to eq(42)
  end

  it "allows querying health checks chronologically" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    db[:schema_health].insert(
      checked_at: "2026-01-01T12:00:00Z",
      schema_version: 5,
      validation_status: "healthy"
    )

    db[:schema_health].insert(
      checked_at: "2026-01-27T12:00:00Z",
      schema_version: 6,
      validation_status: "healthy"
    )

    recent_checks = db[:schema_health]
      .where { checked_at > "2026-01-15T00:00:00Z" }
      .order(:checked_at)
      .all

    expect(recent_checks.length).to eq(1)
    expect(recent_checks.first[:schema_version]).to eq(6)
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 6)

    expect(db.tables).to include(:operation_progress, :schema_health)

    Sequel::Migrator.run(db, migrations_path, target: 5)

    expect(db.tables).not_to include(:operation_progress, :schema_health)
  end
end
