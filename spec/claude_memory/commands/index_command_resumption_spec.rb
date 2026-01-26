# frozen_string_literal: true

require "spec_helper"
require "claude_memory/commands/index_command"
require "claude_memory/store/sqlite_store"
require "claude_memory/infrastructure/operation_tracker"
require "claude_memory/embeddings/generator"
require "fileutils"
require "tmpdir"
require "stringio"

RSpec.describe ClaudeMemory::Commands::IndexCommand, "resumption" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "test.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    # Configure test database path
    allow(ClaudeMemory::Configuration).to receive(:project_db_path).and_return(db_path)

    # Create test facts without embeddings
    entity_id = store.find_or_create_entity(type: "repo", name: "test_repo")
    10.times do |i|
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test_predicate_#{i}",
        object_literal: "value_#{i}",
        scope: "project"
      )
    end

    store.close
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "checkpoint-based resumption" do
    it "creates operation progress record when starting indexing" do
      # Mock embedding generation to be fast
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator)
        .to receive(:generate).and_return([0.1] * 384)

      command.call(["--scope=project", "--batch-size=5"])

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      operations = store.operation_progress.where(operation_type: "index_embeddings", scope: "project").all
      expect(operations.size).to eq(1)
      expect(operations.first[:status]).to eq("completed")
      store.close
    end

    it "resumes from checkpoint after simulated crash" do
      # Mock embedding generation
      call_count = 0
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator).to receive(:generate) do
        call_count += 1
        # Simulate crash after 5 facts
        raise "Simulated crash" if call_count == 6
        [0.1] * 384
      end

      # First run - will crash after 5 facts
      expect {
        command.call(["--scope=project", "--batch-size=5"])
      }.to raise_error("Simulated crash")

      # Verify partial progress was saved
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts_with_embeddings = store.facts.where(Sequel.~(embedding_json: nil)).count
      expect(facts_with_embeddings).to eq(5)  # First batch completed

      # Verify operation is marked as failed
      operation = store.operation_progress
        .where(operation_type: "index_embeddings", scope: "project")
        .order(Sequel.desc(:started_at))
        .first
      expect(operation[:status]).to eq("failed")
      expect(operation[:processed_items]).to eq(5)

      store.close

      # Reset call count and remove crash
      call_count = 0
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator).to receive(:generate) do
        call_count += 1
        [0.2] * 384
      end

      # Mark the failed operation as completed so we can start fresh
      # (in real life user would run recover command)
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      store.operation_progress.where(id: operation[:id]).update(status: "completed")
      store.close

      # Second run - should process remaining 5 facts
      stdout_new = StringIO.new
      command_new = described_class.new(stdout: stdout_new, stderr: stderr)
      command_new.call(["--scope=project", "--batch-size=5"])

      # Verify all facts now have embeddings
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      total_with_embeddings = store.facts.where(Sequel.~(embedding_json: nil)).count
      expect(total_with_embeddings).to eq(10)

      store.close
    end

    it "updates checkpoint after each batch" do
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator)
        .to receive(:generate).and_return([0.1] * 384)

      # Process with batch size 3 (should create 4 batches: 3+3+3+1)
      command.call(["--scope=project", "--batch-size=3"])

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)

      # Verify operation completed successfully
      operation = store.operation_progress
        .where(operation_type: "index_embeddings", scope: "project")
        .first
      expect(operation[:status]).to eq("completed")
      expect(operation[:processed_items]).to eq(10)

      # Verify checkpoint has last fact ID
      checkpoint_data = JSON.parse(operation[:checkpoint_data], symbolize_names: true)
      expect(checkpoint_data[:last_fact_id]).to be > 0

      store.close
    end

    it "handles force flag correctly (ignores checkpoints)" do
      # Index all facts first
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator)
        .to receive(:generate).and_return([0.1] * 384)

      command.call(["--scope=project"])

      # Re-run with --force flag
      stdout_new = StringIO.new
      command_new = described_class.new(stdout: stdout_new, stderr: stderr)

      allow_any_instance_of(ClaudeMemory::Embeddings::Generator)
        .to receive(:generate).and_return([0.2] * 384)

      command_new.call(["--scope=project", "--force"])

      # Verify it processed all facts again (not just new ones)
      output = stdout_new.string
      expect(output).to include("Indexing 10 facts")
    end

    it "completes operation when no facts left to index" do
      # Create a stuck "running" operation
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tracker = ClaudeMemory::Infrastructure::OperationTracker.new(store)

      # First, index all facts
      store.entities.first[:id]
      facts = store.facts.all
      facts.each do |fact|
        store.update_fact_embedding(fact[:id], [0.1] * 384)
      end

      # Create a "running" operation manually
      operation_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        total_items: 10,
        checkpoint_data: {last_fact_id: facts.last[:id]}
      )

      store.close

      # Run index command - should detect no work left and complete operation
      stdout_new = StringIO.new
      command_new = described_class.new(stdout: stdout_new, stderr: stderr)
      command_new.call(["--scope=project"])

      # Verify operation was marked as completed
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      operation = store.operation_progress.where(id: operation_id).first
      expect(operation[:status]).to eq("completed")

      output = stdout_new.string
      expect(output).to include("Resumed operation completed")

      store.close
    end
  end

  describe "transaction safety" do
    it "rolls back batch if error occurs mid-batch" do
      call_count = 0
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator).to receive(:generate) do
        call_count += 1
        # Fail on 3rd fact (within first batch of 5)
        raise "Embedding generation failed" if call_count == 3
        [0.1] * 384
      end

      expect {
        command.call(["--scope=project", "--batch-size=5"])
      }.to raise_error("Embedding generation failed")

      # Verify NO facts have embeddings (entire batch rolled back)
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts_with_embeddings = store.facts.where(Sequel.~(embedding_json: nil)).count
      expect(facts_with_embeddings).to eq(0)

      # Verify checkpoint was not updated (no successful batches)
      operation = store.operation_progress
        .where(operation_type: "index_embeddings", scope: "project")
        .first
      expect(operation[:processed_items]).to eq(0)
      expect(operation[:status]).to eq("failed")

      store.close
    end

    it "commits completed batches before failure" do
      call_count = 0
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator).to receive(:generate) do
        call_count += 1
        # Fail on 6th fact (after first batch of 5)
        raise "Embedding generation failed" if call_count == 6
        [0.1] * 384
      end

      expect {
        command.call(["--scope=project", "--batch-size=5"])
      }.to raise_error("Embedding generation failed")

      # Verify first 5 facts have embeddings (first batch committed)
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts_with_embeddings = store.facts.where(Sequel.~(embedding_json: nil)).count
      expect(facts_with_embeddings).to eq(5)

      # Verify checkpoint reflects completed batch
      operation = store.operation_progress
        .where(operation_type: "index_embeddings", scope: "project")
        .first
      expect(operation[:processed_items]).to eq(5)

      store.close
    end
  end

  describe "stale operation detection" do
    it "cleans up stale operations before starting new one" do
      # Create stale operation (>24h old)
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      old_time = (Time.now.utc - 90000).iso8601  # 25 hours ago
      stale_id = store.operation_progress.insert(
        operation_type: "index_embeddings",
        scope: "project",
        status: "running",
        started_at: old_time
      )
      store.close

      # Run index command
      allow_any_instance_of(ClaudeMemory::Embeddings::Generator)
        .to receive(:generate).and_return([0.1] * 384)

      command.call(["--scope=project"])

      # Verify stale operation was marked as failed
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      stale_op = store.operation_progress.where(id: stale_id).first
      expect(stale_op[:status]).to eq("failed")

      # Verify new operation was created and completed
      operations = store.operation_progress
        .where(operation_type: "index_embeddings", scope: "project", status: "completed")
        .all
      expect(operations.size).to eq(1)
      expect(operations.first[:id]).not_to eq(stale_id)

      store.close
    end
  end
end
