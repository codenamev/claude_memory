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
  end

  describe "#call" do
    describe "memory.status" do
      it "returns system status" do
        create_fact("convention", "test_rule")
        result = tools.call("memory.status", {})

        expect(result[:facts_total]).to eq(1)
        expect(result[:schema_version]).to eq(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION)
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
        expect(result[:error]).to eq("Fact not found")
      end
    end

    describe "unknown tool" do
      it "returns error" do
        result = tools.call("unknown.tool", {})
        expect(result[:error]).to include("Unknown tool")
      end
    end
  end
end
