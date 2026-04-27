# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Sweep::RecallTimestampRefresher do
  let(:tmpdir) { Dir.mktmpdir("refresher_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end
  let(:refresher) { described_class.new(manager) }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def insert_fact(store, scope:)
    entity = store.find_or_create_entity(type: "repo", name: "app")
    store.insert_fact(
      subject_entity_id: entity, predicate: "convention", object_literal: "obj-#{scope}",
      status: "active", scope: scope, confidence: 0.9
    )
  end

  def record_recall(store, scope:, fact_id:, occurred_at: Time.now.utc.iso8601)
    store.activity_events.insert(
      event_type: "recall",
      status: "success",
      occurred_at: occurred_at,
      detail_json: {top_facts_by_scope: {scope => [fact_id]}, result_count: 1}.to_json
    )
  end

  describe "#refresh!" do
    it "writes last_recalled_at on project facts from project events" do
      fact = insert_fact(manager.project_store, scope: "project")
      record_recall(manager.project_store, scope: "project", fact_id: fact)

      counts = refresher.refresh!

      expect(counts[:project]).to eq(1)
      stored = manager.project_store.facts.where(id: fact).first
      expect(stored[:last_recalled_at]).not_to be_nil
    end

    it "updates global facts from events recorded in the project DB" do
      # Global facts are commonly returned from a project context, so the
      # recall event lives in the project's activity_events but the fact
      # row lives in the global DB.
      fact = insert_fact(manager.global_store, scope: "global")
      record_recall(manager.project_store, scope: "global", fact_id: fact)

      counts = refresher.refresh!

      expect(counts[:global]).to eq(1)
      expect(manager.global_store.facts.where(id: fact).first[:last_recalled_at]).not_to be_nil
    end

    it "keeps the most recent occurrence when a fact is touched multiple times" do
      fact = insert_fact(manager.project_store, scope: "project")
      old = (Time.now.utc - 5 * 86_400).iso8601
      newer = (Time.now.utc - 1 * 86_400).iso8601
      record_recall(manager.project_store, scope: "project", fact_id: fact, occurred_at: old)
      record_recall(manager.project_store, scope: "project", fact_id: fact, occurred_at: newer)

      refresher.refresh!

      stored = manager.project_store.facts.where(id: fact).first
      expect(stored[:last_recalled_at]).to eq(newer)
    end

    it "ignores events older than the lookback window" do
      fact = insert_fact(manager.project_store, scope: "project")
      ancient = (Time.now.utc - 200 * 86_400).iso8601
      record_recall(manager.project_store, scope: "project", fact_id: fact, occurred_at: ancient)

      counts = described_class.new(manager, lookback_days: 90).refresh!

      expect(counts[:project]).to eq(0)
      expect(manager.project_store.facts.where(id: fact).first[:last_recalled_at]).to be_nil
    end

    it "no-ops cleanly when no recall events exist" do
      insert_fact(manager.project_store, scope: "project")

      expect(refresher.refresh!).to eq(project: 0, global: 0)
    end
  end
end
