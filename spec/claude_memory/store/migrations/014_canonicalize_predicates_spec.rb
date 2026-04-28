# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 014: Canonicalize Predicates" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    Sequel::Migrator.run(db, migrations_path, target: 13)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  def insert_fact(predicate, object_literal, docid)
    now = Time.now.utc.iso8601
    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "fixture-#{docid}",
      slug: "repo:fixture-#{docid}",
      created_at: now
    )
    db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object_literal,
      status: "active",
      valid_from: now,
      created_at: now,
      scope: "project",
      docid: docid
    )
  end

  it "rewrites has_convention to convention" do
    fact_id = insert_fact("has_convention", "frozen string literal", "deadbeef")
    Sequel::Migrator.run(db, migrations_path, target: 14)
    expect(db[:facts].where(id: fact_id).get(:predicate)).to eq("convention")
  end

  it "rewrites primary_language to uses_language" do
    fact_id = insert_fact("primary_language", "ruby", "f00dface")
    Sequel::Migrator.run(db, migrations_path, target: 14)
    expect(db[:facts].where(id: fact_id).get(:predicate)).to eq("uses_language")
  end

  it "leaves already-canonical predicates untouched" do
    convention_id = insert_fact("convention", "no raw SQL", "abadcafe")
    db_id = insert_fact("uses_database", "sqlite", "1337c0de")

    Sequel::Migrator.run(db, migrations_path, target: 14)

    expect(db[:facts].where(id: convention_id).get(:predicate)).to eq("convention")
    expect(db[:facts].where(id: db_id).get(:predicate)).to eq("uses_database")
  end

  it "preserves docid, object_literal, status, and timestamps when canonicalizing" do
    fact_id = insert_fact("has_convention", "use frozen string literal", "deadbeef")
    before_row = db[:facts].where(id: fact_id).first

    Sequel::Migrator.run(db, migrations_path, target: 14)

    after_row = db[:facts].where(id: fact_id).first
    expect(after_row[:docid]).to eq(before_row[:docid])
    expect(after_row[:object_literal]).to eq(before_row[:object_literal])
    expect(after_row[:status]).to eq(before_row[:status])
    expect(after_row[:created_at]).to eq(before_row[:created_at])
    expect(after_row[:valid_from]).to eq(before_row[:valid_from])
  end

  it "is idempotent — re-running does not double-rewrite" do
    fact_id = insert_fact("has_convention", "x", "deadbeef")

    Sequel::Migrator.run(db, migrations_path, target: 14)
    canonical_predicate = db[:facts].where(id: fact_id).get(:predicate)

    # Drop schema_info back to 13 and re-run; result must match.
    db[:schema_info].update(version: 13)
    Sequel::Migrator.run(db, migrations_path, target: 14)
    expect(db[:facts].where(id: fact_id).get(:predicate)).to eq(canonical_predicate)
  end

  it "down migration is a no-op (cannot reverse a predicate rename)" do
    fact_id = insert_fact("has_convention", "x", "deadbeef")
    Sequel::Migrator.run(db, migrations_path, target: 14)
    expect(db[:facts].where(id: fact_id).get(:predicate)).to eq("convention")

    Sequel::Migrator.run(db, migrations_path, target: 13)

    # Predicate stays canonicalized — there's no original to restore to.
    expect(db[:facts].where(id: fact_id).get(:predicate)).to eq("convention")
  end
end
