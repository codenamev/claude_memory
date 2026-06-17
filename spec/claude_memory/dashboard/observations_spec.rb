# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Observations do
  let(:tmpdir) { Dir.mktmpdir("dashboard_obs_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", "memory.sqlite3") }
  let(:manager) do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path, project_db_path: project_db_path, project_path: tmpdir
    )
  end
  let(:panel) { described_class.new(manager) }
  let(:store) { manager.project_store }

  before { manager.ensure_both! }

  after do
    manager&.close
    FileUtils.rm_rf(tmpdir)
  end

  it "returns a zeroed report when there are no observations" do
    report = panel.report
    expect(report[:totals]).to eq(active: 0, consolidated: 0, expired: 0, promoted: 0)
    expect(report[:recent]).to be_empty
    expect(report[:compression][:ratio]).to be_nil
  end

  describe "with observations" do
    before do
      store.insert_observation(body: "decided to use SQLite", kind: "decision", priority: 1)
      store.insert_observation(body: "prefer small PRs", kind: "preference", priority: 2)
      gone = store.insert_observation(body: "merged away", kind: "event", priority: 3)
      keep = store.insert_observation(body: "kept", kind: "event", priority: 3)
      store.tombstone_observation(gone, into_id: keep)
    end

    it "counts by status, kind, and priority (active only for breakdowns)" do
      report = panel.report
      expect(report[:totals]).to include(active: 3, consolidated: 1)
      expect(report[:by_kind]).to eq("decision" => 1, "preference" => 1, "event" => 1)
      expect(report[:by_priority]).to eq(1 => 1, 2 => 1, 3 => 1)
    end

    it "reports max corroboration and how many are promotable (corroborated + unpromoted)" do
      id = store.insert_observation(body: "recurring", kind: "decision", priority: 1)
      store.increment_corroboration(id, by: 2) # -> 3

      report = panel.report
      expect(report[:corroboration][:max]).to eq(3)
      expect(report[:corroboration][:promotable]).to eq(1)
    end

    it "excludes already-promoted observations from promotable" do
      id = store.insert_observation(body: "done", kind: "decision", priority: 1)
      store.increment_corroboration(id, by: 2)
      store.mark_observation_promoted(id, fact_id: 1)

      expect(panel.report[:corroboration][:promotable]).to eq(0)
    end

    it "computes a compression ratio of source content tokens to observation tokens" do
      cid = store.upsert_content_item(source: "t", text_hash: "h", byte_len: 4000, raw_text: "x" * 4000)
      store.insert_observation(body: "y" * 40, kind: "event", priority: 3, source_content_item_id: cid)

      compression = panel.report[:compression]
      expect(compression[:source_tokens]).to eq(1000)   # 4000 bytes / 4
      expect(compression[:ratio]).to be > 1.0
    end

    it "lists the recent observations newest-first with relative time" do
      recent = panel.report[:recent]
      expect(recent.first).to include(:id, :kind, :priority, :corroboration_count, :body, :observed_ago)

      bodies = recent.map { |o| o[:body] }
      expect(bodies).to include("kept")
      expect(bodies).not_to include("merged away") # tombstoned, excluded
    end
  end
end
