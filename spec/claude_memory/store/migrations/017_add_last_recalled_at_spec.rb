# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"

RSpec.describe "Migration 017: Add last_recalled_at to facts" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    Sequel::Migrator.run(db, migrations_path, target: 16)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  def insert_fact(docid)
    now = Time.now.utc.iso8601
    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "fixture-#{docid}",
      slug: "repo:fixture-#{docid}",
      created_at: now
    )
    db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "convention",
      object_literal: "x",
      status: "active",
      valid_from: now,
      created_at: now,
      scope: "project",
      docid: docid
    )
  end

  it "adds last_recalled_at as a nullable column" do
    Sequel::Migrator.run(db, migrations_path, target: 17)

    columns = db.schema(:facts).map(&:first)
    expect(columns).to include(:last_recalled_at)

    column_info = db.schema(:facts).find { |name, _| name == :last_recalled_at }
    expect(column_info.last[:allow_null]).to be(true)
  end

  it "leaves existing facts with NULL last_recalled_at" do
    fact_id = insert_fact("deadbeef")
    Sequel::Migrator.run(db, migrations_path, target: 17)

    expect(db[:facts].where(id: fact_id).get(:last_recalled_at)).to be_nil
  end

  it "accepts ISO 8601 timestamp writes" do
    fact_id = insert_fact("deadbeef")
    Sequel::Migrator.run(db, migrations_path, target: 17)

    now = Time.now.utc.iso8601
    db[:facts].where(id: fact_id).update(last_recalled_at: now)
    expect(db[:facts].where(id: fact_id).get(:last_recalled_at)).to eq(now)
  end

  it "drops last_recalled_at on down migration" do
    Sequel::Migrator.run(db, migrations_path, target: 17)
    expect(db.schema(:facts).map(&:first)).to include(:last_recalled_at)

    Sequel::Migrator.run(db, migrations_path, target: 16)
    expect(db.schema(:facts).map(&:first)).not_to include(:last_recalled_at)
  end
end
