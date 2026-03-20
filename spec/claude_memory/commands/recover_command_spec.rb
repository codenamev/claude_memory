# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::RecoverCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:global_db_path) { File.join(temp_dir, "global.sqlite3") }
  let(:project_db_path) { File.join(temp_dir, "project.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: temp_dir
    )
  end

  before do
    # Create both databases
    ClaudeMemory::Store::SQLiteStore.new(global_db_path).close
    ClaudeMemory::Store::SQLiteStore.new(project_db_path).close

    # Ensure stores are initialized (RecoverCommand accesses global_store/project_store directly)
    manager.ensure_both!

    allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(manager)
  end

  after do
    manager.close
    FileUtils.rm_rf(temp_dir)
  end

  describe "#call" do
    it "reports no stuck operations when none exist" do
      exit_code = command.call([])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("No stuck operations found")
    end

    it "resets stuck operations older than 24 hours" do
      # Create an operation and backdate it to look stuck (>24h old)
      tracker = ClaudeMemory::Infrastructure::OperationTracker.new(manager.project_store)
      op_id = tracker.start_operation(
        operation_type: "index_embeddings",
        scope: "project",
        total_items: 10,
        checkpoint_data: {last_fact_id: nil}
      )
      stale_time = (Time.now.utc - 86500).iso8601 # >24h ago
      manager.project_store.operation_progress.where(id: op_id).update(started_at: stale_time)

      exit_code = command.call([])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Reset")
    end

    it "filters by scope" do
      exit_code = command.call(["--scope=global"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("No stuck operations found")
    end
  end
end
