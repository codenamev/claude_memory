# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::ReclassifyReferencesCommand do
  let(:tmpdir) { Dir.mktmpdir("reclassify_refs_#{Process.pid}") }
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

  describe "#call" do
    it "prints baseline summary when no facts exist" do
      expect(command.call([])).to eq(0)

      out = stdout.string
      expect(out).to include("RECLASSIFY: scope=project")
      expect(out).to include("Active conventions inspected: 0")
      expect(out).to include("Reclassified as reference:    0")
    end

    it "retags reference-shaped convention facts to predicate=reference" do
      store = manager.project_store
      ref_id = insert_fact(store, predicate: "convention",
        object: "qmd is a tool with 5,700 LOC by Tobi Lütke")
      keep_id = insert_fact(store, predicate: "convention",
        object: "Use 4-space indentation for Ruby files")

      expect(command.call([])).to eq(0)

      expect(store.facts.where(id: ref_id).first[:predicate]).to eq("reference")
      expect(store.facts.where(id: keep_id).first[:predicate]).to eq("convention")

      out = stdout.string
      expect(out).to include("Active conventions inspected: 2")
      expect(out).to include("Reclassified as reference:    1")
      expect(out).to match(/fact ##{ref_id}/)
    end

    it "honors --dry-run by reporting decisions without persisting them" do
      store = manager.project_store
      ref_id = insert_fact(store, predicate: "convention",
        object: "lossless-claw is a CLI by Martian Engineering")

      expect(command.call(["--dry-run"])).to eq(0)

      out = stdout.string
      expect(out).to include("DRY RUN: scope=project")
      expect(out).to include("Reclassified as reference:    1")

      expect(store.facts.where(id: ref_id).first[:predicate]).to eq("convention")
    end

    it "operates on the global scope when --scope global is passed" do
      store = manager.global_store
      ref_id = insert_fact(store, predicate: "convention",
        object: "claude-mem is a plugin with 1,234 stars by Alex Mack")

      expect(command.call(["--scope", "global"])).to eq(0)

      expect(stdout.string).to include("scope=global")
      expect(store.facts.where(id: ref_id).first[:predicate]).to eq("reference")
    end
  end
end
