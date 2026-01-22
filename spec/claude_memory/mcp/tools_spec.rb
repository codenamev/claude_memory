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

    it "includes semantic shortcut tools" do
      defs = tools.definitions
      expect(defs.map { |d| d[:name] }).to include(
        "memory.decisions", "memory.conventions", "memory.architecture"
      )
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

    describe "memory.recall_index" do
      it "returns lightweight index format" do
        # Create content and fact
        content_id = manager.project_store.upsert_content_item(
          source: "test",
          session_id: "sess-1",
          text_hash: "hash",
          byte_len: 20,
          raw_text: "PostgreSQL database"
        )

        fts = ClaudeMemory::Index::LexicalFTS.new(manager.project_store)
        fts.index_content_item(content_id, "PostgreSQL database")

        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
        fact_id = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_database",
          object_literal: "PostgreSQL with connection pooling"
        )

        manager.project_store.insert_provenance(
          fact_id: fact_id,
          content_item_id: content_id,
          quote: "PostgreSQL",
          strength: "stated"
        )

        result = manager_tools.call("memory.recall_index", {
          "query" => "database",
          "limit" => 10
        })

        expect(result[:result_count]).to be > 0
        expect(result[:total_estimated_tokens]).to be > 0

        fact = result[:facts].first
        expect(fact[:id]).to eq(fact_id)
        expect(fact[:predicate]).to eq("uses_database")
        expect(fact[:object_preview].length).to be <= 50
        expect(fact[:tokens]).to be > 0
      end

      it "returns empty when no matches" do
        result = manager_tools.call("memory.recall_index", {"query" => "nonexistent"})

        expect(result[:result_count]).to eq(0)
        expect(result[:facts]).to be_empty
      end
    end

    describe "memory.recall_details" do
      it "fetches full details for fact IDs" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
        fact_id = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_framework",
          object_literal: "Rails with Hotwire"
        )

        content_id = manager.project_store.upsert_content_item(
          source: "test",
          session_id: "sess-1",
          text_hash: "hash",
          byte_len: 10,
          raw_text: "Rails app"
        )

        manager.project_store.insert_provenance(
          fact_id: fact_id,
          content_item_id: content_id,
          quote: "Rails",
          strength: "stated"
        )

        result = manager_tools.call("memory.recall_details", {
          "fact_ids" => [fact_id],
          "scope" => "project"
        })

        expect(result[:fact_count]).to eq(1)

        fact = result[:facts].first
        expect(fact[:fact][:id]).to eq(fact_id)
        expect(fact[:fact][:object]).to eq("Rails with Hotwire")
        expect(fact[:receipts]).to be_an(Array)
        expect(fact[:relationships]).not_to be_nil
      end

      it "handles multiple fact IDs" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
        id1 = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_database",
          object_literal: "PostgreSQL"
        )
        id2 = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_framework",
          object_literal: "Rails"
        )

        result = manager_tools.call("memory.recall_details", {
          "fact_ids" => [id1, id2]
        })

        expect(result[:fact_count]).to eq(2)
      end
    end

    def create_manager_fact_with_content(store, predicate, object, text)
      content_id = store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize,
        raw_text: text
      )

      fts = ClaudeMemory::Index::LexicalFTS.new(store)
      fts.index_content_item(content_id, text)

      entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: predicate,
        object_literal: object
      )

      store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: text,
        strength: "stated"
      )

      fact_id
    end

    describe "memory.decisions" do
      it "returns decision-related facts using shortcut" do
        create_manager_fact_with_content(
          manager.project_store,
          "decision",
          "Use PostgreSQL",
          "We made a decision about the constraint and rule for this requirement"
        )

        result = manager_tools.call("memory.decisions", {"limit" => 10})

        expect(result[:category]).to eq("decisions")
        expect(result[:count]).to be_a(Integer)
        expect(result[:facts]).to be_an(Array)
      end

      it "allows overriding limit" do
        3.times do |i|
          create_manager_fact_with_content(
            manager.project_store,
            "decision",
            "Decision #{i}",
            "Decision #{i} about constraint rule requirement"
          )
        end

        result = manager_tools.call("memory.decisions", {"limit" => 2})

        expect(result[:count]).to be <= 2
      end

      it "uses default limit of 10" do
        result = manager_tools.call("memory.decisions", {})

        expect(result[:facts]).to be_an(Array)
        # Default limit is 10
      end
    end

    describe "memory.conventions" do
      it "returns convention-related facts using shortcut" do
        create_manager_fact_with_content(
          manager.global_store,
          "convention",
          "Use 4-space indentation",
          "Style convention prefer 4 spaces format pattern"
        )

        result = manager_tools.call("memory.conventions", {"limit" => 20})

        expect(result[:category]).to eq("conventions")
        expect(result[:count]).to be_a(Integer)
        expect(result[:facts]).to be_an(Array)
      end

      it "uses higher default limit of 20" do
        result = manager_tools.call("memory.conventions", {})

        expect(result[:facts]).to be_an(Array)
        # Default limit is 20 for conventions
      end

      it "allows overriding limit" do
        5.times do |i|
          create_manager_fact_with_content(
            manager.global_store,
            "convention",
            "Convention #{i}",
            "Style convention #{i} format pattern prefer"
          )
        end

        result = manager_tools.call("memory.conventions", {"limit" => 3})

        expect(result[:count]).to be <= 3
      end
    end

    describe "memory.architecture" do
      it "returns architecture-related facts using shortcut" do
        create_manager_fact_with_content(
          manager.project_store,
          "uses_framework",
          "Rails",
          "This project uses Rails framework and implements MVC architecture pattern"
        )

        result = manager_tools.call("memory.architecture", {"limit" => 10})

        expect(result[:category]).to eq("architecture")
        expect(result[:count]).to be_a(Integer)
        expect(result[:facts]).to be_an(Array)
      end

      it "allows overriding limit" do
        3.times do |i|
          create_manager_fact_with_content(
            manager.project_store,
            "uses_framework",
            "Framework #{i}",
            "Uses framework #{i} architecture pattern implements"
          )
        end

        result = manager_tools.call("memory.architecture", {"limit" => 1})

        expect(result[:count]).to be <= 1
      end
    end
  end
end
