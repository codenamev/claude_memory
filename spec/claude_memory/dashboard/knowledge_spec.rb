# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Knowledge do
  let(:tmpdir) { Dir.mktmpdir("knowledge_test_#{Process.pid}") }
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
  let(:knowledge) { described_class.new(manager) }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def insert(store, predicate:, object:, subject: "app", scope: "project", confidence: 0.9, status: "active")
    entity_id = store.find_or_create_entity(type: "repo", name: subject)
    store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate, object_literal: object,
      status: status, confidence: confidence, scope: scope
    )
  end

  describe "#summary" do
    it "returns the zero shape when empty" do
      data = knowledge.summary
      expect(data[:totals]).to eq(project: 0, global: 0, expiring: {project: 0, global: 0})
      expect(data[:sections].map { |s| s[:key] }).to eq([
        :decisions, :quality_guards, :conventions, :architecture, :constraints, :references
      ])
      expect(data[:sections].map { |s| s[:count] }).to all(eq(0))
    end

    it "routes decision-predicate facts into the Decisions section" do
      insert(manager.project_store, predicate: "decision", object: "Use PostgreSQL for primary storage")
      data = knowledge.summary
      decisions = data[:sections].find { |s| s[:key] == :decisions }
      expect(decisions[:count]).to eq(1)
      expect(decisions[:facts].first[:object]).to eq("Use PostgreSQL for primary storage")
    end

    it "splits convention facts into quality guards when the object starts with Never/Always/Must/Do not" do
      insert(manager.project_store, predicate: "convention", object: "Never commit .env files")
      insert(manager.project_store, predicate: "convention", object: "Always run tests before pushing")
      insert(manager.project_store, predicate: "convention", object: "Prefer composition over inheritance")
      insert(manager.project_store, predicate: "convention", object: "Do not use shared mutable state")

      data = knowledge.summary
      guards = data[:sections].find { |s| s[:key] == :quality_guards }
      convs = data[:sections].find { |s| s[:key] == :conventions }
      expect(guards[:count]).to eq(3)
      expect(convs[:count]).to eq(1)
    end

    it "routes architecture-predicate facts to the Architecture section" do
      insert(manager.project_store, predicate: "architecture", object: "MCP tools delegate to handler modules")
      data = knowledge.summary
      arch = data[:sections].find { |s| s[:key] == :architecture }
      expect(arch[:count]).to eq(1)
    end

    it "routes uses_framework/database/language/platform/auth to the Constraints section" do
      insert(manager.project_store, predicate: "uses_framework", object: "Rails")
      insert(manager.project_store, predicate: "uses_database", object: "PostgreSQL")
      insert(manager.project_store, predicate: "deployment_platform", object: "Fly.io")

      data = knowledge.summary
      constraints = data[:sections].find { |s| s[:key] == :constraints }
      expect(constraints[:count]).to eq(3)
    end

    it "caps shown facts at the limit parameter" do
      5.times { |i| insert(manager.project_store, predicate: "convention", object: "thing #{i}") }
      data = knowledge.summary("limit" => 2)
      convs = data[:sections].find { |s| s[:key] == :conventions }
      expect(convs[:count]).to eq(5)
      expect(convs[:facts].size).to eq(2)
    end

    it "filters to a single section when section= is passed (returns ALL in that section, ignores limit)" do
      3.times { |i| insert(manager.project_store, predicate: "decision", object: "decision #{i}") }
      5.times { |i| insert(manager.project_store, predicate: "convention", object: "conv #{i}") }
      data = knowledge.summary("section" => "decisions", "limit" => 1)
      expect(data[:sections].size).to eq(1)
      expect(data[:sections].first[:key]).to eq(:decisions)
      expect(data[:sections].first[:facts].size).to eq(3) # limit ignored under section filter
    end

    it "scopes to project only when scope=project" do
      insert(manager.project_store, predicate: "decision", object: "proj decision")
      insert(manager.global_store, predicate: "decision", object: "global decision", scope: "global")

      data = knowledge.summary("scope" => "project")
      decisions = data[:sections].find { |s| s[:key] == :decisions }
      expect(decisions[:count]).to eq(1)
      expect(decisions[:facts].first[:object]).to eq("proj decision")
    end

    it "includes both source labels on facts when scope=all" do
      insert(manager.project_store, predicate: "convention", object: "project conv")
      insert(manager.global_store, predicate: "convention", object: "global conv", scope: "global")

      data = knowledge.summary("scope" => "all")
      convs = data[:sections].find { |s| s[:key] == :conventions }
      sources = convs[:facts].map { |f| f[:source] }.uniq.sort
      expect(sources).to eq(%w[global project])
    end

    it "reports totals independently of the section filter" do
      insert(manager.project_store, predicate: "decision", object: "x")
      insert(manager.global_store, predicate: "convention", object: "y", scope: "global")

      data = knowledge.summary
      expect(data[:totals]).to eq(project: 1, global: 1, expiring: {project: 0, global: 0})
    end

    it "counts expiring facts separately from active totals" do
      insert(manager.project_store, predicate: "decision", object: "x")
      insert(manager.project_store, predicate: "convention", object: "y", status: "expiring")

      data = knowledge.summary
      expect(data[:totals]).to eq(project: 1, global: 0, expiring: {project: 1, global: 0})
    end
  end
end
