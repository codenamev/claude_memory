# frozen_string_literal: true

require "spec_helper"
require "claude_memory/store/sqlite_store"
require "sequel"
require "sequel/extensions/migration"
require "fileutils"
require "tmpdir"

# End-to-end migration round-trip from v14 (the boundary shipped by
# v0.9.0 and v0.9.1) to v17 (current). This is the path the majority of
# users will actually take on their next upgrade.
#
# At v14, predicate canonicalization (014) has already run for any facts
# that existed at that point. The remaining work is purely additive
# (mcp_tool_calls already exists from v13, plus 015–017). This spec
# verifies that no canonicalization regressions reintroduce stale names
# and that any post-014 stale-predicate rows stay stale (014 is one-shot
# by design — the Resolver canonicalizes at insert time going forward).
RSpec.describe "Schema round-trip from v14 to v17 (v0.9.x boundary)" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "v14_to_v17.sqlite3") }
  let(:migrations_path) { File.expand_path("../../../../db/migrations", __dir__) }

  after { FileUtils.rm_rf(temp_dir) }

  def build_v14_fixture!
    db = Sequel.connect("extralite:#{db_path}")
    Sequel::Migrator.run(db, migrations_path, target: 14)

    now = Time.now.utc.iso8601

    entity_id = db[:entities].insert(
      type: "repo",
      canonical_name: "fixture_repo_v14",
      slug: "repo:fixture_repo_v14",
      created_at: now
    )

    content_item_id = db[:content_items].insert(
      source: "fixture_session_v14",
      ingested_at: now,
      text_hash: "0" * 64,
      byte_len: 100,
      project_path: "/fixture"
    )

    # At v14, all canonicalized — no stale predicate names.
    fact_seeds = [
      {predicate: "convention", object_literal: "no raw SQL", docid: "abadcafe"},
      {predicate: "uses_language", object_literal: "ruby", docid: "f00dface"},
      {predicate: "uses_database", object_literal: "sqlite", docid: "1337c0de"},
      {predicate: "uses_framework", object_literal: "rails", docid: "ca11ab1e"}
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

    # Sample mcp_tool_calls row (table exists at v14 since v13 added it).
    db[:mcp_tool_calls].insert(
      tool_name: "memory.recall",
      called_at: now,
      duration_ms: 7,
      result_count: 3,
      scope: "project"
    )

    db[:provenance].insert(
      fact_id: fact_ids.first,
      content_item_id: content_item_id,
      strength: "stated"
    )

    db.disconnect
    {entity_id: entity_id, fact_ids: fact_ids, content_item_id: content_item_id}
  end

  describe "fixture sanity" do
    it "leaves the database at v14 with mcp_tool_calls but not v15+ tables" do
      build_v14_fixture!

      db = Sequel.connect("extralite:#{db_path}")
      expect(db[:schema_info].get(:version)).to eq(14)
      expect(db.tables).to include(:mcp_tool_calls)
      expect(db.tables).not_to include(:activity_events, :moment_feedback)
      expect(db.schema(:facts).map(&:first)).not_to include(:last_recalled_at)
      db.disconnect
    end
  end

  describe "auto-migration via SQLiteStore.new" do
    let(:fixture) { build_v14_fixture! }

    it "advances v14 to the current SCHEMA_VERSION" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(store.db[:schema_info].get(:version)).to eq(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION)
      store.close
    end

    it "preserves entities, facts, content items, provenance, and mcp_tool_calls rows" do
      ids = fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db[:entities].where(id: ids[:entity_id]).first[:canonical_name]).to eq("fixture_repo_v14")
      expect(store.facts.count).to eq(4)
      expect(store.db[:provenance].where(fact_id: ids[:fact_ids].first).count).to eq(1)
      expect(store.db[:mcp_tool_calls].count).to eq(1)

      store.close
    end

    it "leaves already-canonical predicates untouched (014 doesn't rerun)" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.facts.where(predicate: "convention").count).to eq(1)
      expect(store.facts.where(predicate: "uses_language").count).to eq(1)
      expect(store.facts.where(predicate: "uses_database").count).to eq(1)
      expect(store.facts.where(predicate: "uses_framework").count).to eq(1)

      store.close
    end

    it "creates activity_events, moment_feedback, and facts.last_recalled_at" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      expect(store.db.tables).to include(:activity_events, :moment_feedback)
      expect(store.db.schema(:facts).map(&:first)).to include(:last_recalled_at)
      expect(store.facts.exclude(last_recalled_at: nil).count).to eq(0)

      store.close
    end

    it "does NOT retroactively canonicalize any stale predicate inserted after the v14 upgrade" do
      # Migration 014 is one-shot. If a v0.9.x user somehow inserted a
      # stale-named row after upgrading (e.g. via a stale resolver path),
      # the v14→v17 chain won't rewrite it — the Resolver's insert-time
      # canonicalization is the only line of defense going forward. This
      # codifies that behavior so anyone tempted to "make 014 idempotent
      # for new rows" knows they'd be changing a contract.
      fixture
      db = Sequel.connect("extralite:#{db_path}")
      now = Time.now.utc.iso8601
      orphan_entity_id = db[:entities].insert(
        type: "repo",
        canonical_name: "post_v14_stale",
        slug: "repo:post_v14_stale",
        created_at: now
      )
      db[:facts].insert(
        subject_entity_id: orphan_entity_id,
        predicate: "has_convention",
        object_literal: "should not be rewritten by migrations",
        status: "active",
        valid_from: now,
        created_at: now,
        scope: "project",
        docid: "5ta1eaf"
      )
      db.disconnect

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(store.facts.where(docid: "5ta1eaf").get(:predicate)).to eq("has_convention")
      store.close
    end

    it "is idempotent on re-open" do
      fixture
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      version_after = store.db[:schema_info].get(:version)
      store.close

      reopened = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(reopened.db[:schema_info].get(:version)).to eq(version_after)
      reopened.close
    end
  end
end
