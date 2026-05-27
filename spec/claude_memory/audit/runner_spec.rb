# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Audit::Runner do
  let(:project_db) { File.join(Dir.tmpdir, "audit_project_#{Process.pid}.sqlite3") }
  let(:global_db) { File.join(Dir.tmpdir, "audit_global_#{Process.pid}.sqlite3") }
  let(:manager) { ClaudeMemory::Store::StoreManager.new(project_db_path: project_db, global_db_path: global_db) }

  after do
    manager.close
    FileUtils.rm_f(project_db)
    FileUtils.rm_f(global_db)
  end

  def insert(store, predicate:, object:, status: "active", scope: "project", subject: "repo")
    entity_id = store.find_or_create_entity(type: "repo", name: subject)
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      status: status,
      scope: scope
    )
  end

  describe "#run" do
    it "returns ok when DB is empty" do
      result = described_class.new(manager: manager).run
      expect(result.findings.select(&:error?)).to be_empty
      expect(result.ok?).to be(true)
      expect(result.exit_code).to eq(0)
    end

    it "detects open conflicts (C001)" do
      manager.ensure_project!
      f1 = insert(manager.project_store, predicate: "uses_database", object: "sqlite")
      f2 = insert(manager.project_store, predicate: "uses_database", object: "postgresql", status: "disputed")
      manager.project_store.insert_conflict(fact_a_id: f1, fact_b_id: f2, notes: "test")

      result = described_class.new(manager: manager).run
      c001 = result.findings.find { |f| f.id == "C001" }
      expect(c001).not_to be_nil
      expect(c001.severity).to eq(:error)
      expect(c001.fact_ids).to include(f1, f2)
    end

    it "detects single-cardinality multiplicity (C002)" do
      manager.ensure_project!
      insert(manager.project_store, predicate: "uses_database", object: "sqlite")
      insert(manager.project_store, predicate: "uses_database", object: "postgresql")

      result = described_class.new(manager: manager).run
      c002 = result.findings.find { |f| f.id == "C002" }
      expect(c002).not_to be_nil
      expect(c002.severity).to eq(:error)
      expect(c002.title).to include("uses_database")
    end

    it "detects single-cardinality churn (C010)" do
      manager.ensure_project!
      6.times do |i|
        insert(manager.project_store, predicate: "uses_database", object: "halluc_#{i}", status: "superseded")
      end

      result = described_class.new(manager: manager).run
      c010 = result.findings.find { |f| f.id == "C010" }
      expect(c010).not_to be_nil
      expect(c010.severity).to eq(:warn)
    end

    it "detects project starvation (C008)" do
      manager.ensure_project!
      insert(manager.project_store, predicate: "decision", object: "the only one we have")

      result = described_class.new(manager: manager).run
      c008 = result.findings.find { |f| f.id == "C008" }
      expect(c008).not_to be_nil
      expect(c008.severity).to eq(:warn)
    end

    it "passes shortcut-leak checks (C004, C005) when shortcuts behave correctly" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "decision", object: "We picked SQLite because operational simplicity")
      insert(manager.project_store, predicate: "convention", object: "Use frozen_string_literal so we avoid mutation bugs")

      result = described_class.new(manager: manager).run
      expect(result.findings.find { |f| f.id == "C004" }).to be_nil
      expect(result.findings.find { |f| f.id == "C005" }).to be_nil
    end

    it "detects duplicate global conventions (C006)" do
      manager.ensure_global!
      insert(manager.global_store, predicate: "convention", object: "uses tmux for session management", scope: "global", subject: "user")
      insert(manager.global_store, predicate: "convention", object: "tmux for session management", scope: "global", subject: "user")

      result = described_class.new(manager: manager).run
      c006 = result.findings.find { |f| f.id == "C006" }
      expect(c006).not_to be_nil
      expect(c006.severity).to eq(:info)
    end

    it "reports bare-conclusion rate (C007) when threshold exceeded" do
      manager.ensure_project!
      8.times { |i| insert(manager.project_store, predicate: "convention", object: "convention #{i}") }
      insert(manager.project_store, predicate: "convention", object: "explained because reasons")

      result = described_class.new(manager: manager).run
      c007 = result.findings.find { |f| f.id == "C007" }
      expect(c007).not_to be_nil
      expect(c007.severity).to eq(:info)
    end

    it "collects per-DB stats" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "decision", object: "p1 because reasons")
      insert(manager.global_store, predicate: "convention", object: "g1 because reasons", scope: "global", subject: "user")

      result = described_class.new(manager: manager).run
      expect(result.stats[:project][:active_facts]).to be >= 1
      expect(result.stats[:global][:active_facts]).to be >= 1
      expect(result.stats[:checks_run]).to eq(described_class::CHECK_METHODS.size)
    end
  end
end
