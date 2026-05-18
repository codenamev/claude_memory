# frozen_string_literal: true

require "spec_helper"
require "claude_memory/store/sqlite_store"
require "sequel"
require "sequel/extensions/migration"
require "fileutils"
require "tmpdir"

# End-to-end migration round-trip from v13 (the 0.9.1 release boundary)
# to v17 (current). Mirrors the upgrade path a 0.9.1 user takes when
# they install a newer gem and the next hook invocation opens their DB
# with the new SQLiteStore. Per-migration specs only verify the delta;
# this spec verifies the full chain plus data preservation, predicate
# canonicalization (014), additive table/column creation (015–017), and
# idempotency on re-open.
RSpec.describe "Schema round-trip from v13 to v17" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "v13_to_v17.sqlite3") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  after { FileUtils.rm_rf(temp_dir) }

  # Builds a v13 database with realistic data: an entity, a content item,
  # and a mix of facts — some using stale predicate names that migration
  # 014 should canonicalize, some using already-current predicates that
  # should be left alone.
  def build_v13_fixture!
    db = Sequel.connect("extralite:#{db_path}")
    Sequel::Migrator.run(db, migrations_path, target: 13)

    now = Time.now.utc.iso8601

    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "fixture_repo",
      slug: "repo:fixture_repo",
      created_at: now
    )

    content_item_id = db[:content_items].insert(
      source: "fixture_session",
      ingested_at: now,
      text_hash: "0" * 64,
      byte_len: 100,
      project_path: "/fixture"
    )

    fact_seeds = [
      {predicate: "has_convention", object_literal: "frozen string literal", docid: "deadbeef"},
      {predicate: "primary_language", object_literal: "ruby", docid: "f00dface"},
      {predicate: "convention", object_literal: "no raw SQL", docid: "abadcafe"},
      {predicate: "uses_database", object_literal: "sqlite", docid: "1337c0de"}
    ]
    fact_ids = fact_seeds.map do |seed|
      db[:facts].insert(
        subject_entity_id: entity_id,
        predicate: seed[:predicate],
        object_literal: seed[:object_literal],
        status: "active",
        valid_from: now,
        created_at: now,
        scope: "project",
        project_path: "/fixture",
        docid: seed[:docid]
      )
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
    it "leaves the database at v13 with the expected pre-migration shape" do
      build_v13_fixture!

      db = Sequel.connect("extralite:#{db_path}")
      expect(db[:schema_info].get(:version)).to eq(13)
      expect(db.tables).to include(:mcp_tool_calls)
      expect(db.tables).not_to include(:activity_events, :moment_feedback)
      expect(db.schema(:facts).map(&:first)).not_to include(:last_recalled_at)
      db.disconnect
    end
  end

  describe "auto-migration via SQLiteStore.new" do
    let(:fixture) { build_v13_fixture! }

    it "advances the database to the current SCHEMA_VERSION" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(store.db[:schema_info].get(:version)).to eq(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION)
      store.close
    end

    it "preserves entities, facts, and provenance from the v13 fixture" do
      ids = fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db[:entities].where(id: ids[:entity_id]).first[:canonical_name]).to eq("fixture_repo")
      expect(store.facts.count).to eq(4)
      expect(store.db[:content_items].where(id: ids[:content_item_id]).first[:byte_len]).to eq(100)
      expect(store.db[:provenance].where(fact_id: ids[:fact_ids].first).count).to eq(1)

      store.close
    end

    it "canonicalizes stale predicates via migration 014" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.facts.where(predicate: "has_convention").count).to eq(0)
      expect(store.facts.where(predicate: "primary_language").count).to eq(0)
      expect(store.facts.where(predicate: "convention").count).to eq(2)  # original + canonicalized has_convention
      expect(store.facts.where(predicate: "uses_language").count).to eq(1)
      expect(store.facts.where(predicate: "uses_database").count).to eq(1)

      store.close
    end

    it "preserves docids when canonicalizing predicates" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      canonicalized = store.facts.where(docid: "deadbeef").first
      expect(canonicalized[:predicate]).to eq("convention")
      expect(canonicalized[:object_literal]).to eq("frozen string literal")

      store.close
    end

    it "creates the activity_events table with the expected indexes (migration 015)" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db.tables).to include(:activity_events)
      columns = store.db.schema(:activity_events).map(&:first)
      expect(columns).to include(:event_type, :session_id, :status, :duration_ms, :detail_json, :occurred_at)

      indexes = store.db["SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='activity_events'"].all.map { |r| r[:name] }
      expect(indexes).to include("idx_activity_events_type", "idx_activity_events_occurred_at", "idx_activity_events_session")

      store.close
    end

    it "creates the moment_feedback table with a unique index on event_id (migration 016)" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db.tables).to include(:moment_feedback)
      columns = store.db.schema(:moment_feedback).map(&:first)
      expect(columns).to include(:event_id, :verdict, :note, :recorded_at)

      now = Time.now.utc.iso8601
      event_id = store.db[:activity_events].insert(
        event_type: "recall",
        status: "success",
        occurred_at: now
      )
      store.db[:moment_feedback].insert(event_id: event_id, verdict: "up", recorded_at: now)
      expect {
        store.db[:moment_feedback].insert(event_id: event_id, verdict: "down", recorded_at: now)
      }.to raise_error(Sequel::UniqueConstraintViolation)

      store.close
    end

    it "adds last_recalled_at to facts as a nullable column (migration 017)" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      columns = store.db.schema(:facts).map(&:first)
      expect(columns).to include(:last_recalled_at)

      # Existing v13 rows should have NULL
      expect(store.facts.exclude(last_recalled_at: nil).count).to eq(0)

      # And the column accepts ISO 8601 timestamps
      now = Time.now.utc.iso8601
      store.facts.where(predicate: "uses_database").update(last_recalled_at: now)
      expect(store.facts.where(predicate: "uses_database").first[:last_recalled_at]).to eq(now)

      store.close
    end

    it "is idempotent on re-open — does not rerun 014 or rewrite predicates" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      version_after_first_open = store.db[:schema_info].get(:version)
      predicates_after_first_open = store.facts.select(:id, :predicate).order(:id).all
      store.close

      reopened = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(reopened.db[:schema_info].get(:version)).to eq(version_after_first_open)
      expect(reopened.facts.select(:id, :predicate).order(:id).all).to eq(predicates_after_first_open)
      reopened.close
    end
  end

  describe "downgrade safety" do
    it "leaves a future-versioned DB alone when an older gem opens it" do
      build_v13_fixture!

      # Simulate a future migration having already run
      db = Sequel.connect("extralite:#{db_path}")
      Sequel::Migrator.run(db, migrations_path, target: 17)
      db[:schema_info].update(version: 999)
      db.disconnect

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(store.db[:schema_info].get(:version)).to eq(999)
      store.close
    end
  end
end
