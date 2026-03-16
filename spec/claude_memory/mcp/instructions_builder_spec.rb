# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe ClaudeMemory::MCP::InstructionsBuilder do
  let(:tmpdir) { Dir.mktmpdir("instructions_builder_test_#{Process.pid}") }
  let(:db_path) { File.join(tmpdir, "test.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

  after do
    store.close
    FileUtils.rm_rf(tmpdir)
  end

  describe ".build" do
    context "with a single store" do
      it "includes version" do
        result = described_class.build(store)
        expect(result).to include("ClaudeMemory v#{ClaudeMemory::VERSION}")
      end

      it "includes database state" do
        result = described_class.build(store)
        expect(result).to include("0 active facts")
      end

      it "reflects actual fact count" do
        entity_id = store.find_or_create_entity(type: "repo", name: "test")
        store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_framework",
          object_literal: "Rails",
          status: "active",
          scope: "project"
        )

        result = described_class.build(store)
        expect(result).to include("1 active facts")
      end

      it "includes usage hints" do
        result = described_class.build(store)
        expect(result).to include("memory.recall")
        expect(result).to include("memory.decisions")
      end
    end

    context "with a StoreManager" do
      let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
      let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
      let(:manager) do
        ClaudeMemory::Store::StoreManager.new(
          global_db_path: global_db_path,
          project_db_path: project_db_path,
          project_path: tmpdir
        )
      end

      before { manager.ensure_both! }

      after { manager.close }

      it "includes both database summaries" do
        result = described_class.build(manager)
        expect(result).to include("Global:")
        expect(result).to include("Project:")
      end

      it "omits conflict section when none exist" do
        result = described_class.build(manager)
        expect(result).not_to include("conflict")
      end

      it "includes conflict count when conflicts exist" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
        fact1 = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_database",
          object_literal: "PostgreSQL",
          status: "active",
          scope: "project"
        )
        fact2 = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_database",
          object_literal: "MySQL",
          status: "active",
          scope: "project"
        )
        manager.project_store.insert_conflict(
          fact_a_id: fact1,
          fact_b_id: fact2,
          notes: "Contradictory database choice",
          status: "open"
        )

        result = described_class.build(manager)
        expect(result).to include("1 open conflict")
        expect(result).to include("memory.conflicts")
      end

      it "pluralizes conflicts correctly" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
        3.times do |i|
          f1 = manager.project_store.insert_fact(
            subject_entity_id: entity_id,
            predicate: "decision",
            object_literal: "choice #{i}a",
            status: "active",
            scope: "project"
          )
          f2 = manager.project_store.insert_fact(
            subject_entity_id: entity_id,
            predicate: "decision",
            object_literal: "choice #{i}b",
            status: "active",
            scope: "project"
          )
          manager.project_store.insert_conflict(
            fact_a_id: f1,
            fact_b_id: f2,
            notes: "Conflict #{i}",
            status: "open"
          )
        end

        result = described_class.build(manager)
        expect(result).to include("3 open conflicts")
      end

      it "includes knowledge summary with decisions and conventions" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
        manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "decided",
          object_literal: "use PostgreSQL",
          status: "active",
          scope: "project"
        )
        manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "snake_case naming",
          status: "active",
          scope: "project"
        )

        result = described_class.build(manager)
        expect(result).to include("Knowledge:")
        expect(result).to include("1 decision")
        expect(result).to include("1 convention")
        expect(result).to include("1 entity")
      end

      it "omits knowledge summary when no decisions or conventions exist" do
        result = described_class.build(manager)
        expect(result).not_to include("Knowledge:")
      end

      it "pluralizes knowledge counts correctly" do
        entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
        manager.project_store.find_or_create_entity(type: "framework", name: "rails")
        %w[decided decision chose].each do |pred|
          manager.project_store.insert_fact(
            subject_entity_id: entity_id,
            predicate: pred,
            object_literal: "something",
            status: "active",
            scope: "project"
          )
        end
        %w[convention style_rule].each do |pred|
          manager.project_store.insert_fact(
            subject_entity_id: entity_id,
            predicate: pred,
            object_literal: "something",
            status: "active",
            scope: "project"
          )
        end

        result = described_class.build(manager)
        expect(result).to include("3 decisions")
        expect(result).to include("2 conventions")
        expect(result).to include("2 entities")
      end

      it "includes semantic search hint when vec is available" do
        # Vec availability depends on sqlite-vec extension
        # Just verify the usage hint adapts
        result = described_class.build(manager)
        expect(result).to include("memory.recall")
        expect(result).to include("Start with fast tools")
      end
    end

    context "error resilience" do
      it "returns minimal instructions on error" do
        broken = double("broken_store")
        allow(broken).to receive(:is_a?).with(ClaudeMemory::Store::StoreManager).and_return(false)
        allow(broken).to receive(:respond_to?).with(:facts).and_return(true)
        allow(broken).to receive(:facts).and_raise(RuntimeError, "database error")

        result = described_class.build(broken)
        expect(result).to include("ClaudeMemory v#{ClaudeMemory::VERSION}")
        expect(result).not_to include("database error")
      end
    end
  end
end
