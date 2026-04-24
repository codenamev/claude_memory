# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Reuse do
  let(:tmpdir) { Dir.mktmpdir("reuse_test_#{Process.pid}") }
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
  let(:reuse) { described_class.new(manager) }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def insert(store, predicate:, object:, scope: "project")
    entity_id = store.find_or_create_entity(type: "repo", name: "app")
    store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate, object_literal: object,
      status: "active", confidence: 0.9, scope: scope
    )
  end

  def record(store, event_type, details, occurred_at: Time.now.utc.iso8601)
    store.activity_events.insert(
      event_type: event_type, status: "success",
      detail_json: details.to_json, occurred_at: occurred_at
    )
  end

  describe "#top" do
    it "returns the empty shape when no events exist" do
      data = reuse.top
      expect(data[:facts]).to eq([])
      expect(data[:event_count]).to eq(0)
    end

    it "counts facts by recall_count across recall events" do
      a = insert(manager.project_store, predicate: "convention", object: "Fact A")
      b = insert(manager.project_store, predicate: "convention", object: "Fact B")
      record(manager.project_store, "recall", {top_fact_ids: [a, b]})
      record(manager.project_store, "recall", {top_fact_ids: [a]})

      data = reuse.top
      expect(data[:event_count]).to eq(2)
      counts = data[:facts].to_h { |f| [f[:object], f[:recall_count]] }
      expect(counts["Fact A"]).to eq(2)
      expect(counts["Fact B"]).to eq(1)
    end

    it "also counts context injection events toward recall_count" do
      a = insert(manager.project_store, predicate: "convention", object: "Fact A")
      record(manager.project_store, "hook_context", {top_fact_ids: [a]})
      record(manager.project_store, "recall", {top_fact_ids: [a]})

      data = reuse.top
      expect(data[:facts].first[:recall_count]).to eq(2)
    end

    it "sorts by recall_count descending" do
      a = insert(manager.project_store, predicate: "convention", object: "Fact A")
      b = insert(manager.project_store, predicate: "convention", object: "Fact B")
      record(manager.project_store, "recall", {top_fact_ids: [a]})
      3.times { record(manager.project_store, "recall", {top_fact_ids: [b]}) }

      data = reuse.top
      expect(data[:facts].map { |f| f[:object] }).to eq(["Fact B", "Fact A"])
    end

    it "ignores events older than the since window" do
      a = insert(manager.project_store, predicate: "convention", object: "Fact A")
      old = (Time.now.utc - 30 * 86_400).iso8601
      record(manager.project_store, "recall", {top_fact_ids: [a]}, occurred_at: old)
      record(manager.project_store, "recall", {top_fact_ids: [a]})

      data = reuse.top("since" => (Time.now.utc - 7 * 86_400).iso8601)
      expect(data[:event_count]).to eq(1)
      expect(data[:facts].first[:recall_count]).to eq(1)
    end

    it "honors the limit parameter" do
      ids = 5.times.map { |i| insert(manager.project_store, predicate: "convention", object: "Fact #{i}") }
      ids.each { |id| record(manager.project_store, "recall", {top_fact_ids: [id]}) }

      data = reuse.top("limit" => 2)
      expect(data[:facts].size).to eq(2)
    end

    it "records last_recalled_at for surface in the UI" do
      a = insert(manager.project_store, predicate: "convention", object: "Fact A")
      ts = (Time.now.utc - 3600).iso8601
      record(manager.project_store, "recall", {top_fact_ids: [a]}, occurred_at: ts)

      data = reuse.top
      expect(data[:facts].first[:last_recalled_at]).to eq(ts)
      expect(data[:facts].first[:last_recalled_ago]).to be_a(String)
    end

    it "ignores rejected/superseded facts referenced by recalls" do
      a = insert(manager.project_store, predicate: "convention", object: "Active fact")
      b = insert(manager.project_store, predicate: "convention", object: "Stale fact")
      manager.project_store.facts.where(id: b).update(status: "superseded")
      record(manager.project_store, "recall", {top_fact_ids: [a, b]})

      data = reuse.top
      objects = data[:facts].map { |f| f[:object] }
      expect(objects).to eq(["Active fact"])
    end
  end
end
