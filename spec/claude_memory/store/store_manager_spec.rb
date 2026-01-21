# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Store::StoreManager do
  let(:test_dir) { File.join(Dir.tmpdir, "store_manager_test_#{Process.pid}") }
  let(:global_db_path) { File.join(test_dir, "global.sqlite3") }
  let(:project_db_path) { File.join(test_dir, "project.sqlite3") }
  let(:manager) do
    described_class.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: test_dir
    )
  end

  before do
    FileUtils.mkdir_p(test_dir)
  end

  after do
    manager.close
    FileUtils.rm_rf(test_dir)
  end

  describe "#promote_fact with transaction safety" do
    it "rolls back global fact if provenance copy fails" do
      manager.ensure_both!

      # Create a fact in project store
      subject_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: subject_id,
        predicate: "convention",
        object_literal: "use tabs",
        scope: "project",
        project_path: test_dir
      )
      manager.project_store.insert_provenance(
        fact_id: fact_id,
        quote: "test quote",
        strength: "stated"
      )

      # Mock provenance copy to fail
      allow(manager).to receive(:copy_provenance).and_raise(StandardError, "Provenance copy failed")

      expect {
        manager.promote_fact(fact_id)
      }.to raise_error(StandardError, "Provenance copy failed")

      # Verify rollback - no global facts should exist
      expect(manager.global_store.facts.count).to eq(0)
      expect(manager.global_store.entities.count).to eq(0)
    end

    it "successfully promotes fact with all operations in transaction" do
      manager.ensure_both!

      # Create a fact in project store
      subject_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: subject_id,
        predicate: "convention",
        object_literal: "use tabs",
        scope: "project",
        project_path: test_dir
      )
      manager.project_store.insert_provenance(
        fact_id: fact_id,
        quote: "test quote",
        strength: "stated"
      )

      global_fact_id = manager.promote_fact(fact_id)

      # Verify all operations succeeded
      expect(global_fact_id).not_to be_nil
      expect(manager.global_store.facts.count).to eq(1)
      expect(manager.global_store.provenance.count).to eq(1)

      global_fact = manager.global_store.facts.where(id: global_fact_id).first
      expect(global_fact[:scope]).to eq("global")
      expect(global_fact[:project_path]).to be_nil
    end

    it "rolls back global entities if fact insertion fails" do
      manager.ensure_both!

      # Create a fact in project store
      subject_id = manager.project_store.find_or_create_entity(type: "repo", name: "test-repo")
      object_id = manager.project_store.find_or_create_entity(type: "database", name: "postgresql")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: subject_id,
        predicate: "uses_database",
        object_entity_id: object_id,
        scope: "project",
        project_path: test_dir
      )

      # Mock insert_fact to fail
      allow(manager.global_store).to receive(:insert_fact).and_raise(StandardError, "Insert failed")

      expect {
        manager.promote_fact(fact_id)
      }.to raise_error(StandardError, "Insert failed")

      # Verify rollback - no global entities should exist
      expect(manager.global_store.entities.count).to eq(0)
    end

    it "returns nil if fact does not exist" do
      manager.ensure_both!
      result = manager.promote_fact(999)
      expect(result).to be_nil
    end
  end

  describe "#ensure_global!" do
    it "creates global store and database directory" do
      expect(File.exist?(global_db_path)).to be false
      manager.ensure_global!
      expect(File.exist?(global_db_path)).to be true
      expect(manager.global_store).not_to be_nil
    end

    it "is idempotent" do
      store1 = manager.ensure_global!
      store2 = manager.ensure_global!
      expect(store1).to equal(store2)
    end
  end

  describe "#ensure_project!" do
    it "creates project store and database directory" do
      expect(File.exist?(project_db_path)).to be false
      manager.ensure_project!
      expect(File.exist?(project_db_path)).to be true
      expect(manager.project_store).not_to be_nil
    end

    it "is idempotent" do
      store1 = manager.ensure_project!
      store2 = manager.ensure_project!
      expect(store1).to equal(store2)
    end
  end

  describe "#ensure_both!" do
    it "creates both stores" do
      manager.ensure_both!
      expect(manager.global_store).not_to be_nil
      expect(manager.project_store).not_to be_nil
    end
  end

  describe "#store_for_scope" do
    it "returns global store for 'global' scope" do
      manager.ensure_global!
      store = manager.store_for_scope("global")
      expect(store).to equal(manager.global_store)
    end

    it "returns project store for 'project' scope" do
      manager.ensure_project!
      store = manager.store_for_scope("project")
      expect(store).to equal(manager.project_store)
    end

    it "raises error for invalid scope" do
      expect {
        manager.store_for_scope("invalid")
      }.to raise_error(ArgumentError, /Invalid scope/)
    end
  end
end
