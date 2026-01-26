# frozen_string_literal: true

require "spec_helper"
require "claude_memory/store/sqlite_store"
require "claude_memory/infrastructure/operation_tracker"
require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Infrastructure::OperationTracker do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "test.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:tracker) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_rf(temp_dir)
  end

  describe "#start_operation" do
    it "creates a new operation progress record" do
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        total_items: 100,
        checkpoint_data: {last_fact_id: nil}
      )

      expect(operation_id).to be > 0

      record = store.operation_progress.where(id: operation_id).first
      expect(record[:operation_type]).to eq("index_embeddings")
      expect(record[:scope]).to eq("project")
      expect(record[:status]).to eq("running")
      expect(record[:total_items]).to eq(100)
      expect(record[:processed_items]).to eq(0)
    end

    it "cleans up stale operations before starting" do
      # Create stale operation (>24h old)
      old_time = (Time.now.utc - 90000).iso8601  # 25 hours ago
      store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )

      # Start new operation
      tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project"
      )

      # Verify stale operation was marked as failed
      stale = store.operation_progress.where(started_at: old_time).first
      expect(stale[:status]).to eq("failed")
      expect(stale[:checkpoint_data]).to include("exceeded 24h timeout")
    end
  end

  describe "#update_progress" do
    it "updates processed items and checkpoint data" do
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        total_items: 100
      )

      tracker.update_progress(
        operation_id,
        processed_items: 50,
        checkpoint_data: {last_fact_id: 123}
      )

      record = store.operation_progress.where(id: operation_id).first
      expect(record[:processed_items]).to eq(50)

      checkpoint = JSON.parse(record[:checkpoint_data], symbolize_names: true)
      expect(checkpoint[:last_fact_id]).to eq(123)
    end

    it "updates only processed items if no checkpoint data provided" do
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        checkpoint_data: {last_fact_id: 100}
      )

      tracker.update_progress(operation_id, processed_items: 75)

      record = store.operation_progress.where(id: operation_id).first
      expect(record[:processed_items]).to eq(75)

      # Original checkpoint data preserved
      checkpoint = JSON.parse(record[:checkpoint_data], symbolize_names: true)
      expect(checkpoint[:last_fact_id]).to eq(100)
    end
  end

  describe "#complete_operation" do
    it "marks operation as completed with timestamp" do
      operation_id = tracker.start_operation(
        operation_type: "sweep",
        scope: "global"
      )

      tracker.complete_operation(operation_id)

      record = store.operation_progress.where(id: operation_id).first
      expect(record[:status]).to eq("completed")
      expect(record[:completed_at]).not_to be_nil
    end
  end

  describe "#fail_operation" do
    it "marks operation as failed with error message" do
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project"
      )

      tracker.fail_operation(operation_id, "Out of memory")

      record = store.operation_progress.where(id: operation_id).first
      expect(record[:status]).to eq("failed")
      expect(record[:completed_at]).not_to be_nil

      checkpoint = JSON.parse(record[:checkpoint_data], symbolize_names: true)
      expect(checkpoint[:error]).to eq("Out of memory")
    end
  end

  describe "#get_checkpoint" do
    it "returns checkpoint data for running operation" do
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        total_items: 100,
        checkpoint_data: {last_fact_id: 50}
      )

      tracker.update_progress(operation_id, processed_items: 50)

      checkpoint = tracker.get_checkpoint(
        operation_type: "index_embeddings",
        scope: "project"
      )

      expect(checkpoint).not_to be_nil
      expect(checkpoint[:operation_id]).to eq(operation_id)
      expect(checkpoint[:processed_items]).to eq(50)
      expect(checkpoint[:total_items]).to eq(100)
      expect(checkpoint[:checkpoint_data][:last_fact_id]).to eq(50)
    end

    it "returns nil if no running operation exists" do
      checkpoint = tracker.get_checkpoint(
        operation_type: "index_embeddings",
        scope: "project"
      )

      expect(checkpoint).to be_nil
    end

    it "returns most recent running operation if multiple exist" do
      # Create older operation
      old_time = (Time.now.utc - 3600).iso8601  # 1 hour ago
      store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )

      # Create newer operation
      new_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        checkpoint_data: {last_fact_id: 100}
      )

      checkpoint = tracker.get_checkpoint(
        operation_type: "index_embeddings",
        scope: "project"
      )

      expect(checkpoint[:operation_id]).to eq(new_id)
    end

    it "ignores completed operations" do
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project"
      )

      tracker.complete_operation(operation_id)

      checkpoint = tracker.get_checkpoint(
        operation_type: "index_embeddings",
        scope: "project"
      )

      expect(checkpoint).to be_nil
    end
  end

  describe "#stuck_operations" do
    it "returns operations running for > 24 hours" do
      # Create stale operation
      old_time = (Time.now.utc - 90000).iso8601  # 25 hours ago
      stale_id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )

      # Create recent operation
      tracker.start_operation(
        operation_type: "sweep",
        scope: "global"
      )

      stuck = tracker.stuck_operations
      expect(stuck.size).to eq(1)
      expect(stuck.first[:id]).to eq(stale_id)
    end

    it "returns empty array if no stuck operations" do
      tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project"
      )

      expect(tracker.stuck_operations).to be_empty
    end
  end

  describe "#reset_stuck_operations" do
    it "marks stuck operations as failed" do
      # Create stale operation
      old_time = (Time.now.utc - 90000).iso8601  # 25 hours ago
      stale_id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )

      count = tracker.reset_stuck_operations

      expect(count).to eq(1)

      record = store.operation_progress.where(id: stale_id).first
      expect(record[:status]).to eq("failed")
      expect(record[:checkpoint_data]).to include("Reset by recover command")
    end

    it "filters by operation_type" do
      old_time = (Time.now.utc - 90000).iso8601

      # Create two stuck operations
      index_id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )

      sweep_id = store.operation_progress.insert(
        operation_type: "sweep",
        scope: "global",
        status: "running",
        started_at: old_time
      )

      count = tracker.reset_stuck_operations(operation_type: "index_embeddings")

      expect(count).to eq(1)

      # Only index operation should be reset
      index_record = store.operation_progress.where(id: index_id).first
      expect(index_record[:status]).to eq("failed")

      sweep_record = store.operation_progress.where(id: sweep_id).first
      expect(sweep_record[:status]).to eq("running")  # Still running
    end

    it "filters by scope" do
      old_time = (Time.now.utc - 90000).iso8601

      project_id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )

      global_id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "global",
        status: "running",
        started_at: old_time
      )

      count = tracker.reset_stuck_operations(scope: "project")

      expect(count).to eq(1)

      project_record = store.operation_progress.where(id: project_id).first
      expect(project_record[:status]).to eq("failed")

      global_record = store.operation_progress.where(id: global_id).first
      expect(global_record[:status]).to eq("running")
    end

    it "returns 0 if no stuck operations" do
      tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project"
      )

      count = tracker.reset_stuck_operations
      expect(count).to eq(0)
    end
  end
end
