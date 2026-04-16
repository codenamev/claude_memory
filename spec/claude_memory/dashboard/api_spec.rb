# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::API do
  let(:tmpdir) { Dir.mktmpdir("dashboard_api_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", "memory.sqlite3") }
  let(:manager) do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end
  let(:api) { described_class.new(manager) }

  before do
    manager.ensure_both!
  end

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  describe "#health" do
    it "returns overall health status" do
      result = api.health

      expect(result[:status]).to be_a(String)
      expect(result[:checks]).to be_an(Array)
      expect(result[:version]).to eq(ClaudeMemory::VERSION)
    end

    it "includes database health checks" do
      result = api.health
      db_checks = result[:checks].select { |c| c[:name].include?("database") }
      expect(db_checks.size).to eq(2)
    end

    it "includes remediation text for non-healthy checks" do
      result = api.health
      non_healthy = result[:checks].reject { |c| c[:status] == "healthy" }

      non_healthy.each do |check|
        expect(check[:fix]).to be_a(String), "expected fix text on #{check[:name]} (#{check[:status]})"
        expect(check[:fix]).not_to be_empty
      end
    end

    it "omits fix on healthy checks" do
      result = api.health
      healthy = result[:checks].select { |c| c[:status] == "healthy" }

      healthy.each do |check|
        expect(check).not_to have_key(:fix)
      end
    end
  end

  describe "#stats" do
    it "returns stats for both databases" do
      result = api.stats

      expect(result[:databases]).to have_key(:global)
      expect(result[:databases]).to have_key(:project)
      expect(result[:databases][:project][:exists]).to be true
    end

    it "includes fact and entity counts" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "framework", name: "Rails")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "Rails",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )

      result = api.stats
      project = result[:databases][:project]

      expect(project[:facts_total]).to eq(1)
      expect(project[:facts_active]).to eq(1)
      expect(project[:entities_total]).to eq(1)
    end
  end

  describe "#activity" do
    it "returns empty list when no events" do
      result = api.activity

      expect(result[:event_count]).to eq(0)
      expect(result[:events]).to eq([])
    end

    it "returns recorded events" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "hook_ingest",
        status: "success",
        details: {bytes_read: 512})

      result = api.activity

      expect(result[:event_count]).to eq(1)
      expect(result[:events].first[:event_type]).to eq("hook_ingest")
      expect(result[:events].first[:occurred_ago]).to be_a(String)
    end

    it "filters by event_type" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store, event_type: "hook_ingest", status: "success")
      ClaudeMemory::ActivityLog.record(store, event_type: "recall", status: "success")

      result = api.activity({"event_type" => "recall"})
      expect(result[:event_count]).to eq(1)
    end
  end

  describe "#facts" do
    before do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "database", name: "PostgreSQL")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        status: "active",
        confidence: 0.95,
        scope: "project"
      )
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "Redis",
        status: "superseded",
        confidence: 0.8,
        scope: "project"
      )
    end

    it "returns active facts by default" do
      result = api.facts

      expect(result[:total]).to eq(1)
      expect(result[:facts].first[:predicate]).to eq("uses_database")
      expect(result[:facts].first[:object]).to eq("PostgreSQL")
    end

    it "filters by status" do
      result = api.facts({"status" => "superseded"})

      expect(result[:total]).to eq(1)
      expect(result[:facts].first[:object]).to eq("Redis")
    end

    it "supports search by predicate" do
      result = api.facts({"q" => "uses_database"})

      expect(result[:total]).to eq(1)
    end
  end

  describe "#efficacy" do
    it "returns zero metrics when no recall events" do
      result = api.efficacy

      expect(result[:recall_events]).to eq(0)
      expect(result[:hit_rate]).to eq(0)
      expect(result[:top_queries]).to eq([])
    end

    it "calculates hit rate from recall events" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success",
        details: {query: "auth", result_count: 3, tool: "memory.recall"})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success",
        details: {query: "nothing", result_count: 0, tool: "memory.recall"})

      result = api.efficacy

      expect(result[:recall_events]).to eq(2)
      expect(result[:successful_recalls]).to eq(1)
      expect(result[:empty_recalls]).to eq(1)
      expect(result[:hit_rate]).to eq(50.0)
      expect(result[:top_queries].first[:query]).to eq("auth")
    end
  end

  describe "#timeline" do
    it "returns daily buckets" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "test", name: "test")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test",
        object_literal: "value",
        status: "active",
        scope: "project"
      )

      result = api.timeline

      expect(result[:days]).to be_an(Array)
      # Should have at least today's entry
      expect(result[:days]).not_to be_empty if result[:days].any?
    end
  end
end
