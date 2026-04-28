# frozen_string_literal: true

require "spec_helper"
require "claude_memory/store/sqlite_store"
require "sequel"
require "sequel/extensions/migration"
require "fileutils"
require "tmpdir"

# End-to-end migration round-trip from v12 (the boundary shipped by
# v0.6.0, v0.7.0, v0.7.1, v0.8.0) to v17 (current). Covers the deepest
# upgrade path a still-supported user can take. Verifies the full chain
# 013 → 017 plus data preservation across every step.
RSpec.describe "Schema round-trip from v12 to v17 (v0.8.0 boundary)" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "v12_to_v17.sqlite3") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  after { FileUtils.rm_rf(temp_dir) }

  def build_v12_fixture!
    db = Sequel.connect("extralite:#{db_path}")
    Sequel::Migrator.run(db, migrations_path, target: 12)

    now = Time.now.utc.iso8601

    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "fixture_repo_v12",
      slug: "repo:fixture_repo_v12",
      created_at: now
    )

    content_item_id = db[:content_items].insert(
      source: "fixture_session_v12",
      ingested_at: now,
      text_hash: "0" * 64,
      byte_len: 100,
      project_path: "/fixture"
    )

    fact_seeds = [
      {predicate: "has_convention", object_literal: "frozen string literal", docid: "deadbeef"},
      {predicate: "primary_language", object_literal: "ruby", docid: "f00dface"},
      {predicate: "convention", object_literal: "no raw SQL", docid: "abadcafe"},
      {predicate: "uses_database", object_literal: "sqlite", docid: "1337c0de"},
      # vec_indexed_at exists at v12 — populate one to verify v12-era data survives
      {predicate: "uses_framework", object_literal: "rails", docid: "ca11ab1e", vec_indexed_at: now}
    ]
    fact_ids = fact_seeds.map do |seed|
      attrs = {
        subject_entity_id: entity_id,
        predicate: seed[:predicate],
        object_literal: seed[:object_literal],
        status: "active",
        valid_from: now,
        created_at: now,
        scope: "project",
        project_path: "/fixture",
        docid: seed[:docid]
      }
      attrs[:vec_indexed_at] = seed[:vec_indexed_at] if seed[:vec_indexed_at]
      db[:facts].insert(**attrs)
    end

    db[:provenance].insert(
      fact_id: fact_ids.first,
      content_item_id: content_item_id,
      strength: "stated"
    )

    db.disconnect
    {entity_id: entity_id, fact_ids: fact_ids, content_item_id: content_item_id}
  end

  describe "fixture sanity" do
    it "leaves the database at v12 with no v13+ tables or columns" do
      build_v12_fixture!

      db = Sequel.connect("extralite:#{db_path}")
      expect(db[:schema_info].get(:version)).to eq(12)
      expect(db.tables).not_to include(:mcp_tool_calls, :activity_events, :moment_feedback)
      expect(db.schema(:facts).map(&:first)).to include(:vec_indexed_at)
      expect(db.schema(:facts).map(&:first)).not_to include(:last_recalled_at)
      db.disconnect
    end
  end

  describe "auto-migration via SQLiteStore.new" do
    let(:fixture) { build_v12_fixture! }

    it "advances the database from v12 all the way to the current SCHEMA_VERSION" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(store.db[:schema_info].get(:version)).to eq(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION)
      expect(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION).to eq(17)
      store.close
    end

    it "creates every table and column added across migrations 013–017" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db.tables).to include(:mcp_tool_calls, :activity_events, :moment_feedback)
      expect(store.db.schema(:facts).map(&:first)).to include(:last_recalled_at)

      store.close
    end

    it "preserves entities, facts, content items, and provenance from the v12 fixture" do
      ids = fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db[:entities].where(id: ids[:entity_id]).first[:canonical_name]).to eq("fixture_repo_v12")
      expect(store.facts.count).to eq(5)
      expect(store.db[:content_items].where(id: ids[:content_item_id]).first[:byte_len]).to eq(100)
      expect(store.db[:provenance].where(fact_id: ids[:fact_ids].first).count).to eq(1)

      store.close
    end

    it "preserves v12-era columns (e.g. vec_indexed_at) through the upgrade chain" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      framework_fact = store.facts.where(docid: "ca11ab1e").first
      expect(framework_fact[:vec_indexed_at]).not_to be_nil
      expect(framework_fact[:predicate]).to eq("uses_framework")

      store.close
    end

    it "canonicalizes stale predicates via migration 014 even when starting from v12" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.facts.where(predicate: "has_convention").count).to eq(0)
      expect(store.facts.where(predicate: "primary_language").count).to eq(0)
      expect(store.facts.where(predicate: "convention").count).to eq(2)
      expect(store.facts.where(predicate: "uses_language").count).to eq(1)

      store.close
    end

    it "is idempotent on re-open after deep upgrade" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      version_after = store.db[:schema_info].get(:version)
      predicates_after = store.facts.select(:id, :predicate).order(:id).all
      store.close

      reopened = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(reopened.db[:schema_info].get(:version)).to eq(version_after)
      expect(reopened.facts.select(:id, :predicate).order(:id).all).to eq(predicates_after)
      reopened.close
    end
  end
end
