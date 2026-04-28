# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::DedupeConflictsCommand do
  let(:tmpdir) { Dir.mktmpdir("dedupe_conflicts_#{Process.pid}") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end

  before do
    manager.ensure_both!
    allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(manager)
  end

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def insert_fact(store, predicate:, object:, status: "active")
    entity_id = store.find_or_create_entity(type: "repo", name: "app")
    store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate,
      object_literal: object, status: status, scope: "project", confidence: 0.9
    )
  end

  def insert_conflict(store, fact_a_id:, fact_b_id:, status: "open")
    store.conflicts.insert(
      fact_a_id: fact_a_id, fact_b_id: fact_b_id,
      status: status, detected_at: Time.now.utc.iso8601,
      notes: "test"
    )
  end

  describe "#call" do
    it "prints baseline summary when no open conflicts exist" do
      expect(command.call([])).to eq(0)

      out = stdout.string
      expect(out).to include("DEDUPE: scope=project")
      expect(out).to include("Conflicts inspected: 0")
      expect(out).to include("Duplicates resolved: 0")
    end

    it "deduplicates conflicts that point at the same (subject, predicate, object) pair" do
      store = manager.project_store
      keeper_a = insert_fact(store, predicate: "uses_database", object: "sqlite")
      dup_b = insert_fact(store, predicate: "uses_database", object: "postgres", status: "disputed")
      dup2_b = insert_fact(store, predicate: "uses_database", object: "postgres", status: "disputed")

      keeper_id = insert_conflict(store, fact_a_id: keeper_a, fact_b_id: dup_b)
      dup_id = insert_conflict(store, fact_a_id: keeper_a, fact_b_id: dup2_b)

      expect(command.call([])).to eq(0)

      out = stdout.string
      expect(out).to include("Conflicts inspected: 2")
      expect(out).to include("Duplicates resolved: 1")
      expect(out).to include("conflict ##{dup_id} -> merged into ##{keeper_id}")

      expect(store.conflicts.where(id: dup_id).first[:status]).to eq("resolved")
      expect(store.conflicts.where(id: keeper_id).first[:status]).to eq("open")
      expect(store.facts.where(id: dup2_b).first[:status]).to eq("rejected")
    end

    it "honors --dry-run by reporting decisions without persisting them" do
      store = manager.project_store
      keeper_a = insert_fact(store, predicate: "uses_database", object: "sqlite")
      dup_b = insert_fact(store, predicate: "uses_database", object: "postgres", status: "disputed")
      dup2_b = insert_fact(store, predicate: "uses_database", object: "postgres", status: "disputed")
      insert_conflict(store, fact_a_id: keeper_a, fact_b_id: dup_b)
      dup_id = insert_conflict(store, fact_a_id: keeper_a, fact_b_id: dup2_b)

      expect(command.call(["--dry-run"])).to eq(0)

      out = stdout.string
      expect(out).to include("DRY RUN: scope=project")
      expect(out).to include("Duplicates resolved: 1")

      expect(store.conflicts.where(id: dup_id).first[:status]).to eq("open")
      expect(store.facts.where(id: dup2_b).first[:status]).to eq("disputed")
    end

    it "operates on the global scope when --scope global is passed" do
      store = manager.global_store
      keeper_a = insert_fact(store, predicate: "convention", object: "always_use_x")
      dup_b = insert_fact(store, predicate: "convention", object: "use_y", status: "disputed")
      dup2_b = insert_fact(store, predicate: "convention", object: "use_y", status: "disputed")
      insert_conflict(store, fact_a_id: keeper_a, fact_b_id: dup_b)
      insert_conflict(store, fact_a_id: keeper_a, fact_b_id: dup2_b)

      expect(command.call(["--scope", "global"])).to eq(0)

      expect(stdout.string).to include("scope=global")
      expect(stdout.string).to include("Duplicates resolved: 1")
    end
  end
end
