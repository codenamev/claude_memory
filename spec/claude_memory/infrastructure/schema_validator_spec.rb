# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Infrastructure::SchemaValidator do
  let(:db_path) { File.join(Dir.tmpdir, "validator_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:validator) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#validate" do
    context "with a healthy database" do
      it "returns valid: true with no error issues" do
        result = validator.validate

        expect(result[:valid]).to be true
        expect(result[:issues].select { |i| i[:severity] == "error" }).to be_empty
      end

      it "records a health check in schema_health table" do
        validator.validate

        health = store.schema_health.order(Sequel.desc(:id)).first
        expect(health[:validation_status]).to eq("healthy")
        expect(health[:schema_version]).to eq(ClaudeMemory::Store::SQLiteStore::SCHEMA_VERSION)
      end
    end

    context "with orphaned provenance records" do
      it "reports orphaned provenance as an error" do
        # Create a fact, link provenance, then delete the fact to orphan it
        entity_id = store.find_or_create_entity(type: "test", name: "orphan_test")
        fact_id = store.insert_fact(subject_entity_id: entity_id, predicate: "test")
        store.insert_provenance(fact_id: fact_id, strength: "stated")
        # Delete fact directly to create orphan (bypass FK with pragma)
        store.db.run("PRAGMA foreign_keys = OFF")
        store.facts.where(id: fact_id).delete
        store.db.run("PRAGMA foreign_keys = ON")

        result = validator.validate

        orphan_issue = result[:issues].find { |i| i[:message].include?("orphaned provenance") }
        expect(orphan_issue).not_to be_nil
        expect(orphan_issue[:severity]).to eq("error")
      end
    end

    context "with invalid fact scope" do
      it "reports invalid scope as an error" do
        entity_id = store.find_or_create_entity(type: "test", name: "test")
        fact_id = store.insert_fact(subject_entity_id: entity_id, predicate: "test", scope: "project")
        store.facts.where(id: fact_id).update(scope: "invalid_scope")

        result = validator.validate

        scope_issue = result[:issues].find { |i| i[:message].include?("invalid scope") }
        expect(scope_issue).not_to be_nil
      end
    end

    context "with embedding dimension mismatch" do
      it "reports dimension mismatch when embedding size differs from expected" do
        entity_id = store.find_or_create_entity(type: "test", name: "test")
        fact_id = store.insert_fact(subject_entity_id: entity_id, predicate: "test")
        wrong_dims = Array.new(100, 0.1)
        store.update_fact_embedding(fact_id, wrong_dims)

        result = validator.validate

        dim_issue = result[:issues].find { |i| i[:message].include?("incorrect dimensions") }
        expect(dim_issue).not_to be_nil
        expect(dim_issue[:severity]).to eq("error")
      end
    end

    context "with correct embeddings" do
      it "passes dimension check" do
        entity_id = store.find_or_create_entity(type: "test", name: "test")
        fact_id = store.insert_fact(subject_entity_id: entity_id, predicate: "test")
        correct_dims = Array.new(384, 0.01)
        store.update_fact_embedding(fact_id, correct_dims)

        result = validator.validate

        dim_issues = result[:issues].select { |i| i[:message].include?("dimensions") }
        expect(dim_issues).to be_empty
      end
    end
  end
end
