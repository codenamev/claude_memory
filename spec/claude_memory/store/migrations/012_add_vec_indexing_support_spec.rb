# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 012: Add Vec Indexing Support" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 011 first
    Sequel::Migrator.run(db, migrations_path, target: 11)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 12)

    columns = db.schema(:facts).map(&:first)
    expect(columns).to include(:vec_indexed_at)
  end

  it "adds vec_indexed_at as nullable column" do
    Sequel::Migrator.run(db, migrations_path, target: 12)

    # Existing facts should have nil vec_indexed_at
    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "test",
      slug: "repo:test",
      created_at: Time.now.utc.iso8601
    )

    fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "uses_framework",
      object_literal: "rails",
      status: "active",
      valid_from: Time.now.utc.iso8601,
      created_at: Time.now.utc.iso8601,
      scope: "project",
      docid: "abcd1234"
    )

    fact = db[:facts].where(id: fact_id).first
    expect(fact[:vec_indexed_at]).to be_nil
  end

  it "allows setting vec_indexed_at timestamp" do
    Sequel::Migrator.run(db, migrations_path, target: 12)

    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "test",
      slug: "repo:test",
      created_at: Time.now.utc.iso8601
    )

    now = Time.now.utc.iso8601
    fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "convention",
      object_literal: "test",
      status: "active",
      valid_from: now,
      created_at: now,
      scope: "project",
      docid: "efgh5678"
    )

    db[:facts].where(id: fact_id).update(vec_indexed_at: now)
    fact = db[:facts].where(id: fact_id).first
    expect(fact[:vec_indexed_at]).to eq(now)
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 12)

    columns = db.schema(:facts).map(&:first)
    expect(columns).to include(:vec_indexed_at)

    Sequel::Migrator.run(db, migrations_path, target: 11)

    columns = db.schema(:facts).map(&:first)
    expect(columns).not_to include(:vec_indexed_at)
  end
end
