# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 002: Add Project Scoping" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 001 first
    Sequel::Migrator.run(db, migrations_path, target: 1)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 2)

    content_items_columns = db.schema(:content_items).map(&:first)
    expect(content_items_columns).to include(:project_path)

    facts_columns = db.schema(:facts).map(&:first)
    expect(facts_columns).to include(:scope, :project_path)
  end

  it "adds scope and project_path indexes to facts" do
    Sequel::Migrator.run(db, migrations_path, target: 2)

    indexes = db.indexes(:facts)
    expect(indexes.keys).to include(:idx_facts_scope, :idx_facts_project)
  end

  it "sets default value for scope column" do
    Sequel::Migrator.run(db, migrations_path, target: 2)

    # Insert a fact without specifying scope
    entity_id = db[:entities].insert(
      type: "person",
      canonical_name: "Test",
      slug: "person:test",
      created_at: Time.now.utc.iso8601
    )

    fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "test_predicate",
      created_at: Time.now.utc.iso8601
    )

    fact = db[:facts].where(id: fact_id).first
    expect(fact[:scope]).to eq("project")
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 2)

    # Verify columns exist
    expect(db.schema(:content_items).map(&:first)).to include(:project_path)
    expect(db.schema(:facts).map(&:first)).to include(:scope, :project_path)

    # Roll back
    Sequel::Migrator.run(db, migrations_path, target: 1)

    # Verify columns removed
    expect(db.schema(:content_items).map(&:first)).not_to include(:project_path)
    expect(db.schema(:facts).map(&:first)).not_to include(:scope, :project_path)
  end

  it "allows querying by scope and project after migration" do
    Sequel::Migrator.run(db, migrations_path, target: 2)

    entity_id = db[:entities].insert(
      type: "person",
      canonical_name: "Test User",
      slug: "person:test-user",
      created_at: Time.now.utc.iso8601
    )

    global_fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "prefers",
      object_literal: "Ruby",
      created_at: Time.now.utc.iso8601,
      scope: "global"
    )

    project_fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "working_on",
      object_literal: "ClaudeMemory",
      created_at: Time.now.utc.iso8601,
      scope: "project",
      project_path: "/Users/test/claude_memory"
    )

    # Query by scope
    global_facts = db[:facts].where(scope: "global").all
    expect(global_facts.length).to eq(1)
    expect(global_facts.first[:id]).to eq(global_fact_id)

    # Query by project_path
    project_facts = db[:facts].where(project_path: "/Users/test/claude_memory").all
    expect(project_facts.length).to eq(1)
    expect(project_facts.first[:id]).to eq(project_fact_id)
  end
end
