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

    it "respects the grace window for never-recalled fresh facts" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "foo", status: "active", scope: "project", confidence: 0.9
      )
      # Created today, never recalled — within grace window so not stale yet.
      expect(trust.snapshot[:needs_review][:stale_facts]).to eq(0)
    end

    it "flags facts past the threshold whose last_recalled_at is also stale" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "old", status: "active", scope: "project", confidence: 0.9
      )
      old_ts = (Time.now.utc - 30 * 86_400).iso8601
      manager.project_store.facts.where(id: fact_id).update(created_at: old_ts, last_recalled_at: old_ts)

      expect(trust.snapshot[:needs_review][:stale_facts]).to eq(1)
    end

    it "reports utilization ratio across extracted-vs-used facts in the window" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      # Extract 3 facts; only 1 will have been used by a recall.
      fact_used = manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "A", status: "active", scope: "project", confidence: 0.9
      )
      manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "B", status: "active", scope: "project", confidence: 0.9
      )
      manager.project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: "C", status: "active", scope: "project", confidence: 0.9
      )
      record_event(manager.project_store, "recall",
        {result_count: 1, top_facts_by_scope: {project: [fact_used]}})

      util = trust.snapshot[:utilization]
      expect(util[:extracted]).to eq(3)
      expect(util[:used_from_extracted]).to eq(1)
      expect(util[:ratio_pct]).to eq(33)
      expect(util[:window_days]).to eq(30)
    end

    it "reports 0% ratio when nothing has been extracted yet" do
      util = trust.snapshot[:utilization]
      expect(util[:extracted]).to eq(0)
      expect(util[:ratio_pct]).to eq(0)
    end

    it "counts a fact used across global+project correctly" do
      # Ensure the (scope, id) pair keying doesn't double-count or drop
      # uses from a non-default scope.
      ge = manager.global_store.find_or_create_entity(type: "repo", name: "user")
      global_fact = manager.global_store.insert_fact(
        subject_entity_id: ge, predicate: "convention",
        object_literal: "global thing", status: "active", scope: "global", confidence: 0.9
      )
      record_event(manager.project_store, "recall",
        {result_count: 1, top_facts_by_scope: {global: [global_fact]}})

      util = trust.snapshot[:utilization]
      expect(util[:extracted]).to eq(1)
      expect(util[:used_from_extracted]).to eq(1)
    end

    it "summarizes moment feedback for the sidebar" do
      manager.project_store.upsert_moment_feedback(event_id: 1, verdict: "up")
      manager.project_store.upsert_moment_feedback(event_id: 2, verdict: "up")
      manager.project_store.upsert_moment_feedback(event_id: 3, verdict: "down")

      feedback = trust.snapshot[:feedback]
      expect(feedback[:up]).to eq(2)
      expect(feedback[:down]).to eq(1)
      expect(feedback[:net]).to eq(1)
      expect(feedback[:ratio_pct]).to eq(67)
    end

    it "returns nil ratio when no feedback exists yet" do
      feedback = trust.snapshot[:feedback]
      expect(feedback[:up]).to eq(0)
      expect(feedback[:down]).to eq(0)
      expect(feedback[:ratio_pct]).to be_nil
    end

    it "returns the zero shape for token_budget when no context events exist" do
      tb = trust.snapshot[:token_budget]
      expect(tb).to include(p50: 0, p95: 0, avg: 0, sample_size: 0, window_days: 30)
    end

    it "computes p50/p95/avg from context_tokens in successful hook_context events" do
      now = Time.now.utc
      # 5 events with token counts: 100, 200, 300, 400, 500 — p50=300, p95=500, avg=300
      [100, 200, 300, 400, 500].each_with_index do |tokens, i|
        record_event(manager.project_store, "hook_context",
          {context_tokens: tokens, context_length: tokens * 4},
          occurred_at: (now - (i + 1) * 3600).iso8601)
      end

      tb = trust.snapshot[:token_budget]
      expect(tb[:sample_size]).to eq(5)
      expect(tb[:p50]).to eq(300)
      expect(tb[:p95]).to eq(500)
      expect(tb[:avg]).to eq(300)
      expect(tb[:window_days]).to eq(30)
    end

    it "ignores events outside the 30-day window" do
      now = Time.now.utc
      record_event(manager.project_store, "hook_context",
        {context_tokens: 1000},
        occurred_at: (now - 31 * 86_400).iso8601)
      record_event(manager.project_store, "hook_context",
        {context_tokens: 200},
        occurred_at: (now - 3600).iso8601)

      tb = trust.snapshot[:token_budget]
      expect(tb[:sample_size]).to eq(1)
      expect(tb[:p50]).to eq(200)
    end

    it "ignores skipped/failed events and rows missing context_tokens" do
      now = Time.now.utc
      record_event(manager.project_store, "hook_context",
        {context_tokens: 500}, status: "skipped",
        occurred_at: (now - 3600).iso8601)
      record_event(manager.project_store, "hook_context",
        {context_length: 999}, # no context_tokens key
        occurred_at: (now - 3600).iso8601)
      record_event(manager.project_store, "hook_context",
        {context_tokens: 250},
        occurred_at: (now - 3600).iso8601)

      tb = trust.snapshot[:token_budget]
      expect(tb[:sample_size]).to eq(1)
      expect(tb[:p50]).to eq(250)
    end
  end
end
