# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Trust do
  let(:tmpdir) { Dir.mktmpdir("trust_test_#{Process.pid}") }
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
  let(:trust) { described_class.new(manager) }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def record_event(store, event_type, details, status: "success", occurred_at: Time.now.utc.iso8601)
    store.activity_events.insert(
      event_type: event_type,
      status: status,
      detail_json: details.to_json,
      occurred_at: occurred_at
    )
  end

  def seed_global_fact(predicate:, object:, subject: "user", confidence: 0.95)
    entity_id = manager.global_store.find_or_create_entity(type: "concept", name: subject)
    manager.global_store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      status: "active",
      scope: "global",
      confidence: confidence
    )
  end

  describe "#snapshot" do
    it "returns the zero shape when the stores are empty" do
      data = trust.snapshot
      expect(data[:weekly_moments]).to eq(this_week: 0, last_week: 0, delta: 0, by_kind: {})
      expect(data[:fingerprint]).to eq([])
      expect(data[:needs_review][:open_conflicts][:total]).to eq(0)
    end

    it "counts only value-producing events in the weekly moments total" do
      now = Time.now.utc
      # This week (value-producing)
      record_event(manager.project_store, "recall", {result_count: 1},
        occurred_at: (now - 3600).iso8601)
      record_event(manager.project_store, "store_extraction", {facts_created: 2},
        occurred_at: (now - 7200).iso8601)
      # This week (plumbing — should NOT count)
      record_event(manager.project_store, "hook_ingest", {bytes_read: 100},
        occurred_at: (now - 1800).iso8601)
      # Last week
      record_event(manager.project_store, "recall", {result_count: 1},
        occurred_at: (now - 10 * 86_400).iso8601)

      data = trust.snapshot[:weekly_moments]
      expect(data[:this_week]).to eq(2)
      expect(data[:last_week]).to eq(1)
      expect(data[:delta]).to eq(1)
      expect(data[:by_kind]).to include("recall" => 1, "store_extraction" => 1)
    end

    it "renders fingerprint global facts as plain-English sentences" do
      seed_global_fact(predicate: "convention", object: "uses ag instead of rg")
      seed_global_fact(predicate: "uses_framework", object: "Rails")
      seed_global_fact(predicate: "uses_database", object: "PostgreSQL")

      sentences = trust.snapshot[:fingerprint].map { |f| f[:sentence] }
      expect(sentences).to include("uses ag instead of rg")
      expect(sentences).to include("Uses Rails")
      expect(sentences).to include("Uses PostgreSQL for storage")
    end

    it "caps the fingerprint at 5 facts" do
      7.times { |i| seed_global_fact(predicate: "convention", object: "convention #{i}", subject: "user#{i}") }
      expect(trust.snapshot[:fingerprint].size).to eq(5)
    end

    it "reports needs_review counts including open conflicts across both scopes" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      fact_a = manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "uses_database",
        object_literal: "Postgres", status: "active", scope: "project", confidence: 0.9
      )
      fact_b = manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "uses_database",
        object_literal: "MySQL", status: "disputed", scope: "project", confidence: 0.7
      )
      manager.project_store.insert_conflict(fact_a_id: fact_a, fact_b_id: fact_b)

      review = trust.snapshot[:needs_review]
      expect(review[:open_conflicts][:project]).to eq(1)
      expect(review[:open_conflicts][:total]).to eq(1)
    end

    it "counts zero-result recall events in needs_review" do
      now = Time.now.utc
      record_event(manager.project_store, "recall", {result_count: 0},
        occurred_at: (now - 3600).iso8601)
      record_event(manager.project_store, "recall", {result_count: 0},
        occurred_at: (now - 7200).iso8601)
      record_event(manager.project_store, "recall", {result_count: 4},
        occurred_at: (now - 1800).iso8601)

      expect(trust.snapshot[:needs_review][:empty_recalls]).to eq(2)
    end

    it "does not flag stale facts when no recalls have happened" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "foo", status: "active", scope: "project", confidence: 0.9
      )
      expect(trust.snapshot[:needs_review][:stale_facts]).to eq(0)
    end
  end
end
