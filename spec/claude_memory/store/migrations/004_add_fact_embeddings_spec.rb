# frozen_string_literal: true

require "spec_helper"
require "sequel"
require "sequel/extensions/migration"
require "tmpdir"
require "json"

RSpec.describe "Migration 004: Add Fact Embeddings" do
  let(:db_path) { File.join(Dir.mktmpdir, "test_migration.db") }
  let(:db) { Sequel.connect("extralite:#{db_path}") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  before do
    # Run up to migration 003 first
    Sequel::Migrator.run(db, migrations_path, target: 3)
  end

  after do
    db.disconnect
    File.unlink(db_path) if File.exist?(db_path)
  end

  it "runs migration up successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 4)

    facts_columns = db.schema(:facts).map(&:first)
    expect(facts_columns).to include(:embedding_json)
  end

  it "allows storing JSON embeddings in facts" do
    Sequel::Migrator.run(db, migrations_path, target: 4)

    entity_id = db[:entities].insert(
      type: "person",
      canonical_name: "Test User",
      slug: "person:test-user",
      created_at: Time.now.utc.iso8601
    )

    embedding = [0.1, 0.2, 0.3, 0.4, 0.5] * 100  # 500-dimensional vector
    fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "prefers",
      object_literal: "Ruby",
      created_at: Time.now.utc.iso8601,
      embedding_json: JSON.generate(embedding)
    )

    fact = db[:facts].where(id: fact_id).first
    expect(fact[:embedding_json]).not_to be_nil

    parsed_embedding = JSON.parse(fact[:embedding_json])
    expect(parsed_embedding).to be_an(Array)
    expect(parsed_embedding.length).to eq(500)
    expect(parsed_embedding.first).to eq(0.1)
  end

  it "allows null embeddings for facts without semantic indexing" do
    Sequel::Migrator.run(db, migrations_path, target: 4)

    entity_id = db[:entities].insert(
      type: "person",
      canonical_name: "Test User",
      slug: "person:test-user",
      created_at: Time.now.utc.iso8601
    )

    fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "prefers",
      object_literal: "Python",
      created_at: Time.now.utc.iso8601
    )

    fact = db[:facts].where(id: fact_id).first
    expect(fact[:embedding_json]).to be_nil
  end

  it "can query for facts with and without embeddings" do
    Sequel::Migrator.run(db, migrations_path, target: 4)

    entity_id = db[:entities].insert(
      type: "person",
      canonical_name: "Test User",
      slug: "person:test-user",
      created_at: Time.now.utc.iso8601
    )

    # Create fact with embedding
    embedded_fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "prefers",
      object_literal: "Ruby",
      created_at: Time.now.utc.iso8601,
      embedding_json: JSON.generate([0.1, 0.2, 0.3])
    )

    # Create fact without embedding
    non_embedded_fact_id = db[:facts].insert(
      subject_entity_id: entity_id,
      predicate: "dislikes",
      object_literal: "Java",
      created_at: Time.now.utc.iso8601
    )

    facts_with_embeddings = db[:facts].exclude(embedding_json: nil).all
    expect(facts_with_embeddings.length).to eq(1)
    expect(facts_with_embeddings.first[:id]).to eq(embedded_fact_id)

    facts_without_embeddings = db[:facts].where(embedding_json: nil).all
    expect(facts_without_embeddings.length).to eq(1)
    expect(facts_without_embeddings.first[:id]).to eq(non_embedded_fact_id)
  end

  it "runs migration down successfully" do
    Sequel::Migrator.run(db, migrations_path, target: 4)

    expect(db.schema(:facts).map(&:first)).to include(:embedding_json)

    Sequel::Migrator.run(db, migrations_path, target: 3)

    expect(db.schema(:facts).map(&:first)).not_to include(:embedding_json)
  end
end
