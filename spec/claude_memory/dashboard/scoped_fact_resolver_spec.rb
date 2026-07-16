# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::ScopedFactResolver do
  let(:tmpdir) { Dir.mktmpdir("resolver_test_#{Process.pid}") }
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

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def insert(store, object:, scope:)
    e = store.find_or_create_entity(type: "repo", name: "app")
    store.insert_fact(
      subject_entity_id: e, predicate: "convention", object_literal: object,
      status: "active", scope: scope, confidence: 0.9
    )
  end

  describe ".scoped_ids_from_details" do
    it "prefers top_facts_by_scope when present (authoritative)" do
      details = {"top_facts_by_scope" => {"global" => [1, 2], "project" => [5]},
                 "top_fact_ids" => [1, 2, 5]}
      expect(described_class.scoped_ids_from_details(details)).to eq(
        "global" => [1, 2], "project" => [5]
      )
    end

    it "falls back to top_fact_ids + single-scope results_by_scope" do
      # Historical event: recall ran against global only, so every ID must
      # be a global-DB ID even though the detail doesn't say so directly.
      details = {"top_fact_ids" => [1, 3, 4],
                 "results_by_scope" => {"global" => 10}}
      expect(described_class.scoped_ids_from_details(details)).to eq("global" => [1, 3, 4])
    end

    it "defaults to project when results_by_scope is multi-scope or missing" do
      details = {"top_fact_ids" => [1, 3],
                 "results_by_scope" => {"project" => 2, "global" => 1}}
      expect(described_class.scoped_ids_from_details(details)).to eq("project" => [1, 3])
    end

    it "returns empty when no fact references exist" do
      expect(described_class.scoped_ids_from_details({})).to eq({})
    end
  end

  describe ".resolve" do
    it "resolves IDs from the correct DB by scope" do
      # Project fact #1 and global fact #1 are different facts — this is
      # exactly the bug the resolver exists to prevent.
      project_fact_1 = insert(manager.project_store, object: "project-only convention", scope: "project")
      global_fact_1 = insert(manager.global_store, object: "Docker for containerization", scope: "global")
      expect(project_fact_1).to eq(1)
      expect(global_fact_1).to eq(1)

      scoped = {"global" => [1]}
      resolved = described_class.resolve(manager, scoped)
      expect(resolved.size).to eq(1)
      expect(resolved.first[:object]).to eq("Docker for containerization")
      expect(resolved.first[:source]).to eq("global")
    end

    it "preserves order within each scope" do
      a = insert(manager.project_store, object: "A", scope: "project")
      b = insert(manager.project_store, object: "B", scope: "project")
      c = insert(manager.project_store, object: "C", scope: "project")
      scoped = {"project" => [c, a, b]}
      resolved = described_class.resolve(manager, scoped)
      expect(resolved.map { |f| f[:object] }).to eq(%w[C A B])
    end

    it "tags each resolved fact with its source scope" do
      p = insert(manager.project_store, object: "P", scope: "project")
      g = insert(manager.global_store, object: "G", scope: "global")
      scoped = {"project" => [p], "global" => [g]}
      resolved = described_class.resolve(manager, scoped)
      sources = resolved.to_h { |f| [f[:object], f[:source]] }
      expect(sources).to eq("P" => "project", "G" => "global")
    end
  end

  describe ".flat_pairs" do
    it "flattens {scope => ids} into unique [scope, id] pairs" do
      pairs = described_class.flat_pairs("project" => [1, 2], "global" => [1, 3])
      expect(pairs).to contain_exactly(["project", 1], ["project", 2], ["global", 1], ["global", 3])
    end
  end

  describe "batch resolution (build_fact_index + resolve_from_index)" do
    it "merges many events' scoped ids into one deduped {scope => ids}" do
      d1 = {"top_facts_by_scope" => {"project" => [1, 2]}}
      d2 = {"top_facts_by_scope" => {"project" => [2, 3], "global" => [1]}}
      merged = described_class.merge_scoped_ids([d1, d2])
      expect(merged["project"]).to eq([1, 2, 3])
      expect(merged["global"]).to eq([1])
    end

    it "resolves each event from a shared index with one query per scope, not per event" do
      p = insert(manager.project_store, object: "P", scope: "project")
      g = insert(manager.global_store, object: "G", scope: "global")
      details = [
        {"top_facts_by_scope" => {"project" => [p]}},
        {"top_facts_by_scope" => {"global" => [g]}},
        {"top_facts_by_scope" => {"project" => [p], "global" => [g]}}
      ]
      index = described_class.build_fact_index(manager, described_class.merge_scoped_ids(details))

      # Two scopes touched ⇒ index has exactly the two scope buckets.
      expect(index.keys).to contain_exactly("project", "global")
      # build_fact_index does not re-query per event; resolve_from_index is pure.
      expect(manager.project_store).not_to receive(:facts)
      expect(described_class.resolve_from_index(details[0], index).map { |f| f[:object] }).to eq(%w[P])
      expect(described_class.resolve_from_index(details[1], index).map { |f| f[:source] }).to eq(%w[global])
      expect(described_class.resolve_from_index(details[2], index).map { |f| f[:object] }).to eq(%w[P G])
    end

    it "preserves per-scope input order when resolving from the index" do
      a = insert(manager.project_store, object: "A", scope: "project")
      b = insert(manager.project_store, object: "B", scope: "project")
      c = insert(manager.project_store, object: "C", scope: "project")
      details = {"top_facts_by_scope" => {"project" => [c, a, b]}}
      index = described_class.build_fact_index(manager, described_class.merge_scoped_ids([details]))
      expect(described_class.resolve_from_index(details, index).map { |f| f[:object] }).to eq(%w[C A B])
    end

    it "returns [] from resolve_from_index for events with no scoped facts" do
      expect(described_class.resolve_from_index({}, {})).to eq([])
    end

    it "emits a repeated id once (matching the query-based resolve's row-set dedup)" do
      p = insert(manager.project_store, object: "P", scope: "project")
      details = {"top_facts_by_scope" => {"project" => [p, p]}}
      index = described_class.build_fact_index(manager, described_class.merge_scoped_ids([details]))
      expect(described_class.resolve_from_index(details, index).map { |f| f[:object] }).to eq(%w[P])
    end
  end
end
