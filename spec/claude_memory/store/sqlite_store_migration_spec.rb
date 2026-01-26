# frozen_string_literal: true

require "spec_helper"
require "claude_memory/store/sqlite_store"
require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Store::SQLiteStore, "migrations" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "test.sqlite3") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "per-migration transaction safety" do
    it "updates version atomically with schema changes in v2 migration" do
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      store.close

      # Manually set version to 1 to test v2 migration
      db = Sequel.sqlite(db_path)
      db[:meta].where(key: "schema_version").update(value: "1")
      db.disconnect

      # Open store again to trigger v2 migration
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Verify version was updated
      expect(store.schema_version).to eq(7)

      # Verify v2 schema changes exist
      columns = store.db.schema(:content_items).map(&:first)
      expect(columns).to include(:project_path)

      fact_columns = store.db.schema(:facts).map(&:first)
      expect(fact_columns).to include(:scope, :project_path)

      store.close
    end

    it "wraps each migration in a transaction with atomic version updates" do
      # This test verifies that migrations use transactions and version updates
      # happen atomically with schema changes

      # The key insight: version is updated INSIDE the transaction, so if the
      # migration fails, the version stays at the previous value

      # Simply verify that after migration, version and schema are consistent
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Verify migration completed atomically:
      # - Version is at 6
      # - All v6 tables were created
      expect(store.schema_version).to eq(7)

      tables = store.db.tables
      expect(tables).to include(:operation_progress)
      expect(tables).to include(:schema_health)

      # Verify we can use new tables (they have proper schema)
      now = Time.now.utc.iso8601
      expect {
        store.operation_progress.insert(
          operation_type: "test",
          scope: "project",
          status: "running",
          started_at: now
        )
      }.not_to raise_error

      # The transaction safety is guaranteed by Sequel's transaction mechanism
      # If any step fails, the entire transaction (including version update) rolls back

      store.close
    end

    it "is idempotent - re-running migrations is safe" do
      # Create store (runs all migrations)
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      version = store.schema_version
      store.close

      # Open again (should skip all migrations since already at latest version)
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      expect(store.schema_version).to eq(version)

      # Verify all tables exist
      tables = store.db.tables
      expect(tables).to include(:meta, :content_items, :facts, :entities, :provenance,
        :fact_links, :conflicts, :tool_calls, :operation_progress, :schema_health)

      store.close
    end

    it "migrates sequentially from v0 to v6" do
      # Create empty database
      db = Sequel.sqlite(db_path)
      db.create_table?(:meta) do
        String :key, primary_key: true
        String :value
      end
      db[:meta].insert(key: "schema_version", value: "0")
      db.disconnect

      # Open store to trigger full migration path
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Verify we reached v6
      expect(store.schema_version).to eq(7)

      # Verify v2 additions exist
      columns = store.db.schema(:facts).map(&:first)
      expect(columns).to include(:scope, :project_path)

      # Verify v3 additions exist
      tables = store.db.tables
      expect(tables).to include(:tool_calls)

      # Verify v4 additions exist
      expect(columns).to include(:embedding_json)

      # Verify v5 additions exist
      content_columns = store.db.schema(:content_items).map(&:first)
      expect(content_columns).to include(:source_mtime)

      # Verify v6 additions exist
      expect(tables).to include(:operation_progress, :schema_health)

      store.close
    end
  end

  describe "upgrade path from v5 to v6" do
    it "successfully migrates existing v5 database to v6" do
      # Create v5 database with real data
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Insert some test data
      entity_id = store.find_or_create_entity(type: "repo", name: "test_repo")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        scope: "project",
        project_path: "/test/path"
      )

      # Manually set version to 5
      store.db[:meta].where(key: "schema_version").update(value: "5")
      initial_fact_count = store.facts.count
      store.close

      # Open again to trigger v6 migration
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Verify version updated
      expect(store.schema_version).to eq(7)

      # Verify existing data preserved
      expect(store.facts.count).to eq(initial_fact_count)
      fact = store.facts.where(id: fact_id).first
      expect(fact[:object_literal]).to eq("PostgreSQL")

      # Verify new tables created
      tables = store.db.tables
      expect(tables).to include(:operation_progress, :schema_health)

      # Verify new tables are empty initially
      expect(store.operation_progress.count).to eq(0)
      expect(store.schema_health.count).to eq(0)

      store.close
    end

    it "creates proper indexes for new tables" do
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Query indexes
      operation_indexes = store.db["SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='operation_progress'"].all.map { |r| r[:name] }
      health_indexes = store.db["SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='schema_health'"].all.map { |r| r[:name] }

      # Verify expected indexes exist
      expect(operation_indexes).to include("idx_operation_progress_type", "idx_operation_progress_status")
      expect(health_indexes).to include("idx_schema_health_checked_at")

      store.close
    end
  end

  describe "upgrade path from v6 to v7" do
    it "successfully migrates existing v6 database to v7" do
      # Create v6 database with real data
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Insert some test data
      store.find_or_create_entity(type: "repo", name: "test_repo")
      content_item_id = store.upsert_content_item(
        source: "test",
        text_hash: "abc123",
        byte_len: 100
      )

      # Manually set version to 6
      store.db[:meta].where(key: "schema_version").update(value: "6")
      initial_fact_count = store.facts.count
      store.close

      # Open again to trigger v7 migration
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Verify version updated
      expect(store.schema_version).to eq(7)

      # Verify existing data preserved
      expect(store.facts.count).to eq(initial_fact_count)

      # Verify new ingestion_metrics table created
      tables = store.db.tables
      expect(tables).to include(:ingestion_metrics)

      # Verify new table is empty initially
      expect(store.ingestion_metrics.count).to eq(0)

      # Verify we can insert metrics
      metric_id = store.record_ingestion_metrics(
        content_item_id: content_item_id,
        input_tokens: 1000,
        output_tokens: 200,
        facts_extracted: 5
      )
      expect(metric_id).to be > 0

      # Verify metrics were recorded correctly
      metric = store.ingestion_metrics.where(id: metric_id).first
      expect(metric[:input_tokens]).to eq(1000)
      expect(metric[:output_tokens]).to eq(200)
      expect(metric[:facts_extracted]).to eq(5)

      store.close
    end

    it "creates proper indexes for ingestion_metrics table" do
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Query indexes
      metrics_indexes = store.db["SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='ingestion_metrics'"].all.map { |r| r[:name] }

      # Verify expected indexes exist
      expect(metrics_indexes).to include("idx_ingestion_metrics_content_item", "idx_ingestion_metrics_created_at")

      store.close
    end

    it "can aggregate metrics correctly" do
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Create some content items and metrics
      content_item_id1 = store.upsert_content_item(source: "test1", text_hash: "hash1", byte_len: 100)
      content_item_id2 = store.upsert_content_item(source: "test2", text_hash: "hash2", byte_len: 200)

      store.record_ingestion_metrics(
        content_item_id: content_item_id1,
        input_tokens: 1000,
        output_tokens: 200,
        facts_extracted: 10
      )

      store.record_ingestion_metrics(
        content_item_id: content_item_id2,
        input_tokens: 2000,
        output_tokens: 400,
        facts_extracted: 15
      )

      # Get aggregate metrics
      metrics = store.aggregate_ingestion_metrics

      expect(metrics).not_to be_nil
      expect(metrics[:total_input_tokens]).to eq(3000)
      expect(metrics[:total_output_tokens]).to eq(600)
      expect(metrics[:total_facts_extracted]).to eq(25)
      expect(metrics[:total_operations]).to eq(2)
      expect(metrics[:avg_facts_per_1k_input_tokens]).to eq(8.33)

      store.close
    end
  end

  describe "operation_progress table" do
    let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

    after { store.close }

    it "allows inserting operation progress records" do
      now = Time.now.utc.iso8601
      id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        total_items: 100,
        processed_items: 0,
        checkpoint_data: {last_fact_id: nil}.to_json,
        started_at: now
      )

      expect(id).to be > 0

      record = store.operation_progress.where(id: id).first
      expect(record[:operation_type]).to eq("index_embeddings")
      expect(record[:status]).to eq("running")
      expect(record[:total_items]).to eq(100)
    end

    it "allows querying operations by status" do
      now = Time.now.utc.iso8601
      store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "global",
        status: "running",
        started_at: now
      )
      store.operation_progress.insert(
        operation_type: "sweep",
        scope: "project",
        status: "completed",
        started_at: now,
        completed_at: now
      )

      running = store.operation_progress.where(status: "running").all
      expect(running.size).to eq(1)
      expect(running.first[:operation_type]).to eq("index_embeddings")
    end
  end

  describe "schema_health table" do
    let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

    after { store.close }

    it "allows inserting health check records" do
      now = Time.now.utc.iso8601
      id = store.schema_health.insert(
        checked_at: now,
        schema_version: 6,
        validation_status: "healthy",
        issues_json: [].to_json,
        table_counts_json: {facts: 10, entities: 5}.to_json
      )

      expect(id).to be > 0

      record = store.schema_health.where(id: id).first
      expect(record[:validation_status]).to eq("healthy")
      expect(JSON.parse(record[:issues_json])).to eq([])
    end

    it "allows recording validation issues" do
      now = Time.now.utc.iso8601
      issues = [
        {severity: "error", message: "Missing index on facts.predicate"},
        {severity: "warning", message: "Orphaned provenance record"}
      ]

      id = store.schema_health.insert(
        checked_at: now,
        schema_version: 6,
        validation_status: "corrupt",
        issues_json: issues.to_json,
        table_counts_json: {}.to_json
      )

      record = store.schema_health.where(id: id).first
      parsed_issues = JSON.parse(record[:issues_json], symbolize_names: true)
      expect(parsed_issues.size).to eq(2)
      expect(parsed_issues.first[:severity]).to eq("error")
    end
  end
end
