# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Shortcuts do
  let(:project_db) { File.join(Dir.tmpdir, "shortcuts_project_#{Process.pid}.sqlite3") }
  let(:global_db) { File.join(Dir.tmpdir, "shortcuts_global_#{Process.pid}.sqlite3") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(project_db_path: project_db, global_db_path: global_db)
  end

  after do
    manager&.close
    FileUtils.rm_f(project_db)
    FileUtils.rm_f(global_db)
  end

  def insert(store, predicate:, object:, status: "active", subject: "repo", scope: "project")
    entity_id = store.find_or_create_entity(type: "repo", name: subject)
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      status: status,
      scope: scope
    )
  end

  describe "::SHORTCUTS" do
    it "defines a predicate list for each shortcut" do
      ClaudeMemory::Shortcuts::SHORTCUTS.each_value do |config|
        expect(config[:predicates]).to be_an(Array)
        expect(config[:predicates]).not_to be_empty
        expect(config[:limit]).to be_a(Integer)
      end
    end

    it "decisions filters to predicate=decision only" do
      expect(ClaudeMemory::Shortcuts::SHORTCUTS[:decisions][:predicates]).to eq(%w[decision])
    end

    it "conventions filters to predicate=convention only" do
      expect(ClaudeMemory::Shortcuts::SHORTCUTS[:conventions][:predicates]).to eq(%w[convention])
    end

    it "architecture includes the stack-shaping predicates" do
      preds = ClaudeMemory::Shortcuts::SHORTCUTS[:architecture][:predicates]
      expect(preds).to include("architecture", "uses_database", "uses_framework", "uses_language")
    end
  end

  describe ".for" do
    it "returns project conventions (not only global) — regression for v0.11 audit" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "convention", object: "Project rule A")
      insert(manager.global_store, predicate: "convention", object: "Global rule G", scope: "global")

      results = described_class.for(:conventions, manager)

      objects = results.map { |r| r[:fact][:object_literal] }
      expect(objects).to include("Project rule A")
      expect(objects).to include("Global rule G")
    end

    it "does NOT return uses_database facts under the decisions shortcut" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "uses_database", object: "sqlite")
      insert(manager.project_store, predicate: "decision", object: "Use SQLite because operational simplicity")

      results = described_class.for(:decisions, manager)

      objects = results.map { |r| r[:fact][:object_literal] }
      expect(objects).to include("Use SQLite because operational simplicity")
      expect(objects).not_to include("sqlite")
    end

    it "does NOT return convention facts under the architecture shortcut" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "convention", object: "Some style rule")
      insert(manager.project_store, predicate: "architecture", object: "Dual DB router")

      results = described_class.for(:architecture, manager)

      objects = results.map { |r| r[:fact][:object_literal] }
      expect(objects).to include("Dual DB router")
      expect(objects).not_to include("Some style rule")
    end

    it "includes stack constraints (uses_database, uses_framework) under architecture" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "uses_database", object: "sqlite")
      insert(manager.project_store, predicate: "uses_language", object: "ruby")

      results = described_class.for(:architecture, manager)

      objects = results.map { |r| r[:fact][:object_literal] }
      expect(objects).to include("sqlite", "ruby")
    end

    it "filters out rejected and superseded facts" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "decision", object: "Kept", status: "active")
      insert(manager.project_store, predicate: "decision", object: "Rejected", status: "rejected")
      insert(manager.project_store, predicate: "decision", object: "Superseded", status: "superseded")

      results = described_class.for(:decisions, manager)

      objects = results.map { |r| r[:fact][:object_literal] }
      expect(objects).to eq(["Kept"])
    end

    it "respects the limit override" do
      manager.ensure_both!
      5.times { |i| insert(manager.project_store, predicate: "convention", object: "C#{i}") }

      results = described_class.for(:conventions, manager, limit: 2)

      expect(results.size).to eq(2)
    end

    it "annotates source on each result" do
      manager.ensure_both!
      insert(manager.project_store, predicate: "decision", object: "P")
      insert(manager.global_store, predicate: "decision", object: "G", scope: "global")

      results = described_class.for(:decisions, manager)

      sources = results.map { |r| r[:source] }
      expect(sources).to contain_exactly("project", "global")
    end

    it "raises KeyError for unknown shortcuts" do
      expect { described_class.for(:nonexistent, manager) }.to raise_error(KeyError)
    end
  end

  describe "convenience methods" do
    before { manager.ensure_both! }

    it ".decisions delegates to :decisions shortcut" do
      insert(manager.project_store, predicate: "decision", object: "D1")
      expect(described_class.decisions(manager).map { |r| r[:fact][:object_literal] }).to eq(["D1"])
    end

    it ".architecture delegates to :architecture shortcut" do
      insert(manager.project_store, predicate: "architecture", object: "A1")
      expect(described_class.architecture(manager).map { |r| r[:fact][:object_literal] }).to eq(["A1"])
    end

    it ".conventions delegates to :conventions shortcut" do
      insert(manager.project_store, predicate: "convention", object: "C1")
      expect(described_class.conventions(manager).map { |r| r[:fact][:object_literal] }).to eq(["C1"])
    end

    it ".project_config delegates to :project_config shortcut" do
      insert(manager.project_store, predicate: "uses_database", object: "sqlite")
      expect(described_class.project_config(manager).map { |r| r[:fact][:object_literal] }).to eq(["sqlite"])
    end
  end
end
