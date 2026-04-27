# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Recall::StaleDetector do
  let(:tmpdir) { Dir.mktmpdir("stale_detector_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def insert_aged_fact(store, scope:, last_recalled_days_ago: nil, created_days_ago: 0)
    entity = store.find_or_create_entity(type: "repo", name: "app")
    fact_id = store.insert_fact(
      subject_entity_id: entity, predicate: "convention", object_literal: "obj-#{rand(1_000_000)}",
      status: "active", scope: scope, confidence: 0.9
    )
    created_at = (Time.now.utc - created_days_ago * 86_400).iso8601
    last_recalled_at = last_recalled_days_ago && (Time.now.utc - last_recalled_days_ago * 86_400).iso8601
    store.facts.where(id: fact_id).update(created_at: created_at, last_recalled_at: last_recalled_at)
    fact_id
  end

  describe ".stale_facts" do
    it "returns active facts older than the threshold whose last_recalled_at is also stale" do
      stale = insert_aged_fact(manager.project_store, scope: "project",
        last_recalled_days_ago: 30, created_days_ago: 60)
      _fresh = insert_aged_fact(manager.project_store, scope: "project",
        last_recalled_days_ago: 1, created_days_ago: 60)

      result = described_class.stale_facts(manager, threshold_days: 14)

      expect(result[:total]).to eq(1)
      expect(result[:project].first[:id]).to eq(stale)
    end

    it "treats a never-recalled fact as stale only when it's past the grace window" do
      old_unused = insert_aged_fact(manager.project_store, scope: "project",
        last_recalled_days_ago: nil, created_days_ago: 30)
      _fresh_unused = insert_aged_fact(manager.project_store, scope: "project",
        last_recalled_days_ago: nil, created_days_ago: 2)

      result = described_class.stale_facts(manager, threshold_days: 14)

      expect(result[:project].map { |r| r[:id] }).to eq([old_unused])
    end

    it "spans both stores" do
      pid = insert_aged_fact(manager.project_store, scope: "project",
        last_recalled_days_ago: 60, created_days_ago: 60)
      gid = insert_aged_fact(manager.global_store, scope: "global",
        last_recalled_days_ago: 60, created_days_ago: 60)

      result = described_class.stale_facts(manager, threshold_days: 14)

      expect(result[:project].first[:id]).to eq(pid)
      expect(result[:global].first[:id]).to eq(gid)
      expect(result[:total]).to eq(2)
    end

    it "ignores rejected/superseded facts" do
      entity = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      manager.project_store.insert_fact(
        subject_entity_id: entity, predicate: "convention", object_literal: "rejected",
        status: "rejected", scope: "project", confidence: 0.9
      )

      expect(described_class.stale_facts(manager, threshold_days: 14)[:total]).to eq(0)
    end

    it "honors the limit per scope" do
      3.times do
        insert_aged_fact(manager.project_store, scope: "project",
          last_recalled_days_ago: 30, created_days_ago: 60)
      end

      result = described_class.stale_facts(manager, threshold_days: 14, limit: 2)

      expect(result[:project].size).to eq(2)
    end
  end

  describe ".stale_count" do
    it "matches stale_facts total without materializing rows" do
      insert_aged_fact(manager.project_store, scope: "project",
        last_recalled_days_ago: 30, created_days_ago: 60)
      insert_aged_fact(manager.global_store, scope: "global",
        last_recalled_days_ago: 30, created_days_ago: 60)

      expect(described_class.stale_count(manager, threshold_days: 14)).to eq(2)
    end
  end
end
