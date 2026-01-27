# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 001: Create Initial Schema" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.sqlite(db_path) }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 1)

    expect(db.tables).to include(
      :meta,
      :content_items,
      :delta_cursors,
      :entities,
      :entity_aliases,
      :facts,
      :provenance,
      :fact_links,
      :conflicts,
      :schema_info
    )
  end

  it "creates all expected indexes" do
    Sequel::Migrator.run(db, migrations_path, target: 1)

    indexes = db.indexes(:facts)
    expect(indexes.keys).to include(
      :idx_facts_predicate,
      :idx_facts_subject,
      :idx_facts_status,
      :idx_facts_scope,
      :idx_facts_project
    )

    expect(db.indexes(:provenance).keys).to include(:idx_provenance_fact)
    expect(db.indexes(:entity_aliases).keys).to include(:idx_entity_aliases_entity)
    expect(db.indexes(:content_items).keys).to include(
      :idx_content_items_session,
      :idx_content_items_project
    )
  end

  it "creates facts table with correct columns" do
    Sequel::Migrator.run(db, migrations_path, target: 1)

    schema = db.schema(:facts)
    columns = schema.map { |col| col[0] }

    expect(columns).to include(
      :id,
      :subject_entity_id,
      :predicate,
      :object_entity_id,
      :object_literal,
      :datatype,
      :polarity,
      :valid_from,
      :valid_to,
      :status,
      :confidence,
      :created_from,
      :created_at,
      :scope,
      :project_path
    )
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 1)
    expect(db.tables).to include(:facts)

    Sequel::Migrator.run(db, migrations_path, target: 0)

    expect(db.tables).not_to include(
      :meta,
      :content_items,
      :delta_cursors,
      :entities,
      :entity_aliases,
      :facts,
      :provenance,
      :fact_links,
      :conflicts
    )
    expect(db.tables).to include(:schema_info)  # Sequel's migration tracking table
  end

  it "can insert and query data after migration" do
    Sequel::Migrator.run(db, migrations_path, target: 1)

    # Insert test data
    entity_id = db[:entities].insert(
      type: "person",
      canonical_name: "Test User",
      slug: "test-user",
      created_at: Time.now.utc.iso8601
    )

    fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "prefers",
      object_literal: "Ruby",
      created_at: Time.now.utc.iso8601,
      scope: "global"
    )

    # Query data
    fact = db[:facts].where(id: fact_id).first
    expect(fact[:predicate]).to eq("prefers")
    expect(fact[:object_literal]).to eq("Ruby")
    expect(fact[:scope]).to eq("global")
  end
end
