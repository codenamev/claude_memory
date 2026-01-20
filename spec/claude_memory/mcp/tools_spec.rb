# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::MCP::Tools do
  let(:db_path) { File.join(Dir.tmpdir, "mcp_tools_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:tools) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_fact(predicate, object)
    entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object
    )
  end

  describe "#definitions" do
    it "returns tool definitions" do
      defs = tools.definitions
      expect(defs).to be_an(Array)
      expect(defs.map { |d| d[:name] }).to include(
        "memory.recall", "memory.explain", "memory.changes",
        "memory.conflicts", "memory.sweep_now", "memory.status"
      )
    end

    it "includes promote tool" do
      defs = tools.definitions
      expect(defs.map { |d| d[:name] }).to include("memory.promote")
    end
  end

  describe "#call" do
    describe "memory.status" do
      it "returns system status with legacy store" do
        create_fact("convention", "test_rule")
        result = tools.call("memory.status", {})

        expect(result[:databases][:legacy][:facts_total]).to eq(1)
        expect(result[:databases][:legacy][:schema_version]).to eq(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION)
      end
    end

    describe "memory.conflicts" do
      it "returns open conflicts" do
        fact_a = create_fact("uses_database", "mysql")
        fact_b = create_fact("uses_database", "postgresql")
        store.insert_conflict(fact_a_id: fact_a, fact_b_id: fact_b)

        result = tools.call("memory.conflicts", {})
        expect(result[:count]).to eq(1)
        expect(result[:conflicts].first[:fact_a]).to eq(fact_a)
      end
    end

    describe "memory.sweep_now" do
      it "runs sweep and returns stats" do
        result = tools.call("memory.sweep_now", {"budget_seconds" => 2})
        expect(result).to include(:proposed_expired, :elapsed_seconds)
      end
    end

    describe "memory.explain" do
      it "explains a fact" do
        fact_id = create_fact("convention", "use snake_case")
        result = tools.call("memory.explain", {"fact_id" => fact_id})

        expect(result[:fact][:predicate]).to eq("convention")
        expect(result[:fact][:object]).to eq("use snake_case")
      end

      it "returns error for missing fact" do
        result = tools.call("memory.explain", {"fact_id" => 999})
        expect(result[:error]).to include("Fact not found")
      end
    end

    describe "memory.promote" do
      it "returns error when using legacy store" do
        fact_id = create_fact("convention", "use tabs")
        result = tools.call("memory.promote", {"fact_id" => fact_id})

        expect(result[:error]).to include("StoreManager")
      end
    end

    describe "unknown tool" do
      it "returns error" do
        result = tools.call("unknown.tool", {})
        expect(result[:error]).to include("Unknown tool")
      end
    end
  end

  describe "with StoreManager" do
    let(:tmpdir) { Dir.mktmpdir("mcp_tools_manager_#{Process.pid}") }
    let(:global_db) { File.join(tmpdir, "global.sqlite3") }
    let(:project_db) { File.join(tmpdir, "project.sqlite3") }
    let(:manager) do
      ClaudeMemory::Store::StoreManager.new(
        global_db_path: global_db,
        project_db_path: project_db
      )
    end
    let(:manager_tools) { described_class.new(manager) }

    before do
      manager.ensure_both!
    end

    after do
      manager.close
      FileUtils.rm_rf(tmpdir)
    end

    describe "memory.status" do
      it "returns status for both databases" do
        result = manager_tools.call("memory.status", {})

        expect(result[:databases][:global][:exists]).to be true
        expect(result[:databases][:project][:exists]).to be true
      end
    end

    describe "memory.promote" do
      it "promotes a project fact to global" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
        fact_id = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "use tabs"
        )

        result = manager_tools.call("memory.promote", {"fact_id" => fact_id})

        expect(result[:success]).to be true
        expect(result[:project_fact_id]).to eq(fact_id)
        expect(result[:global_fact_id]).to be_a(Integer)

        global_fact = manager.global_store.facts.first
        expect(global_fact[:object_literal]).to eq("use tabs")
      end

      it "returns error for non-existent fact" do
        result = manager_tools.call("memory.promote", {"fact_id" => 999})
        expect(result[:error]).to include("not found")
      end
    end
  end
end
