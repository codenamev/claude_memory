# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Recall Failure Modes" do
  let(:test_dir) { File.join(Dir.tmpdir, "recall_failure_test_#{Process.pid}") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: File.join(test_dir, "global.sqlite3"),
      project_db_path: File.join(test_dir, "project.sqlite3")
    )
  end
  let(:recall) { ClaudeMemory::Recall.new(manager) }

  before do
    FileUtils.mkdir_p(test_dir)
    manager.ensure_both!
  end

  after do
    manager.close
    FileUtils.rm_rf(test_dir)
  end

  describe "database connection failures" do
    context "when global database connection is lost mid-query" do
      it "raises DatabaseError (TODO: implement graceful degradation)" do
        # Insert test data in project store
        entity_id = manager.project_store.find_or_create_entity(type: "application", name: "test_app")
        content_id = manager.project_store.upsert_content_item(
          source: "test",
          text_hash: "abc123",
          byte_len: 100,
          session_id: "test_session",
          project_path: test_dir
        )

        project_fact_id = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "uses_database",
          object_literal: "PostgreSQL",
          scope: "project",
          project_path: test_dir
        )

        manager.project_store.insert_provenance(
          fact_id: project_fact_id,
          content_item_id: content_id,
          quote: "test quote"
        )

        # Simulate global database failure
        allow(manager).to receive(:global_store).and_raise(Sequel::DatabaseError.new("Connection lost"))

        # Currently raises error - future improvement would be to gracefully degrade
        expect {
          recall.query("PostgreSQL", scope: "all")
        }.to raise_error(Sequel::DatabaseError, /Connection lost/)
      end
    end

    context "when both databases unavailable" do
      it "returns empty results without crashing" do
        allow(manager).to receive(:project_exists?).and_return(false)
        allow(manager).to receive(:global_exists?).and_return(false)

        results = recall.query("test", scope: "all")
        expect(results).to eq([])
      end
    end

    context "when store returns nil" do
      it "handles nil store gracefully" do
        allow(manager).to receive(:project_store).and_return(nil)
        allow(manager).to receive(:global_store).and_return(nil)

        results = recall.query("test", scope: "all")
        expect(results).to eq([])
      end
    end
  end

  describe "concurrent access" do
    context "when multiple queries execute simultaneously" do
      it "handles concurrent read access safely" do
        # Insert test data
        entity_id = manager.project_store.find_or_create_entity(type: "application", name: "test")
        fact_id = manager.project_store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "status",
          object_literal: "active",
          scope: "project",
          project_path: test_dir
        )

        # Execute concurrent queries
        threads = 5.times.map do
          Thread.new do
            recall.query("test", scope: "project", limit: 10)
          end
        end

        results = threads.map(&:value)

        # All threads should complete successfully
        expect(results.size).to eq(5)
        expect(results).to all(be_an(Array))
      end
    end
  end

  describe "data validation" do
    context "when fact missing required fields" do
      it "raises ArgumentError with clear message" do
        expect {
          ClaudeMemory::Domain::Fact.new(
            id: 1,
            subject_name: "test",
            predicate: nil,  # Missing required field
            object_literal: "value",
            status: "active"
          )
        }.to raise_error(ArgumentError, /predicate/)
      end
    end

    context "when scope is invalid" do
      it "handles invalid scope gracefully" do
        # Invalid scope should not crash, might return empty or use default
        expect {
          recall.query("test", scope: "invalid_scope")
        }.not_to raise_error
      end
    end
  end

  describe "empty result handling" do
    context "when no facts match query" do
      it "returns empty array" do
        results = recall.query("nonexistent_term_xyz", scope: "all")
        expect(results).to eq([])
      end
    end

    context "when database is empty" do
      it "returns empty array" do
        results = recall.query("anything", scope: "all")
        expect(results).to eq([])
      end
    end
  end

  describe "malformed data handling" do
    context "when FTS index is corrupted or missing" do
      it "handles FTS errors gracefully" do
        # Drop FTS table to simulate corruption
        manager.project_store.db.drop_table?(:content_fts)

        # Should handle missing FTS table without crashing
        expect {
          recall.query("test", scope: "project")
        }.not_to raise_error
      end
    end
  end
end
