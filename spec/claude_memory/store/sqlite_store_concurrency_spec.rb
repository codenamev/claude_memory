# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "timeout"

RSpec.describe ClaudeMemory::Store::SQLiteStore, "concurrency" do
  let(:db_path) { File.join(Dir.tmpdir, "claude_memory_concurrency_#{Process.pid}.sqlite3") }

  after do
    FileUtils.rm_f(db_path)
    FileUtils.rm_f("#{db_path}-wal")
    FileUtils.rm_f("#{db_path}-shm")
  end

  describe "multi-process database access" do
    # This spec reproduces the real-world failure:
    #   - Multiple hook processes try to connect simultaneously
    #   - "database is locked" error occurs at connection time
    #
    # The error occurs because:
    # 1. Extralite/Sequel runs PRAGMA statements in connect_sqls during connection
    # 2. PRAGMA journal_mode = WAL requires a lock
    # 3. Multiple processes trying to set WAL mode simultaneously can fail
    #
    # From the error: "Ran 3 stop hooks" - Claude Code runs multiple hooks
    # in parallel, and they all try to open the database at the same moment.

    it "allows multiple simultaneous connections from separate processes" do
      # First, create the database so WAL mode is already set
      setup_store = described_class.new(db_path)
      entity_id = setup_store.find_or_create_entity(type: "test", name: "project")
      setup_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test_predicate",
        object_literal: "test_value"
      )
      setup_store.close

      # Now simulate 3 hook processes trying to connect simultaneously
      # This is exactly what happens when Claude Code runs stop hooks
      pipes = 3.times.map { IO.pipe }
      pids = []

      3.times do |i|
        _, writer = pipes[i]

        pids << fork do
          # Close all readers in child
          pipes.each { |r, _w| r.close }
          # Close other writers
          pipes.each_with_index { |(_r, w), j| w.close if j != i }

          begin
            # This is what HookCommand does - creates new SQLiteStore
            hook_store = described_class.new(db_path)

            # Perform a write operation (what ingest hook does)
            # Using transaction_with_retry to handle concurrent access
            hook_store.transaction_with_retry do
              hook_store.upsert_content_item(
                source: "hook_#{i}",
                session_id: "test-session",
                text_hash: "hash_#{i}_#{Time.now.to_f}",
                byte_len: 100,
                raw_text: "content from hook #{i}"
              )
            end

            count = hook_store.content_items.count
            hook_store.close
            writer.puts "success:#{count}"
          rescue Sequel::DatabaseConnectionError, Sequel::DatabaseError, Extralite::Error => e
            writer.puts "error:#{e.class}:#{e.message}"
          ensure
            writer.close
          end
        end
      end

      # Close writers in parent
      pipes.each { |_r, w| w.close }

      # Collect results with timeout
      results = []
      Timeout.timeout(45) do # busy_timeout is 30s, give some headroom
        pids.each { |pid| Process.wait(pid) }
        results = pipes.map { |r, _w| r.read.strip.tap { r.close } }
      end

      # All 3 hook processes should succeed
      results.each_with_index do |result, i|
        expect(result).to start_with("success:"),
          "Hook process #{i + 1} failed: #{result}"
      end
    end

    it "allows read access while another process writes (WAL mode)" do
      # In WAL mode, readers don't block writers and vice versa
      # This tests that a child process can read while parent does writes
      setup_store = described_class.new(db_path)
      entity_id = setup_store.find_or_create_entity(type: "test", name: "project")
      setup_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "initial",
        object_literal: "value"
      )
      setup_store.close

      writer_store = described_class.new(db_path)
      reader_pipe, writer_pipe = IO.pipe

      # Fork a reader process
      child_pid = fork do
        reader_pipe.close

        begin
          reader_store = described_class.new(db_path)
          # Just read - should never be blocked by writes in WAL mode
          count = reader_store.facts.count
          reader_store.close
          writer_pipe.puts "success:#{count}"
        rescue Sequel::DatabaseConnectionError, Sequel::DatabaseError, Extralite::Error => e
          writer_pipe.puts "error:#{e.class}:#{e.message}"
        ensure
          writer_pipe.close
        end
      end

      writer_pipe.close

      # Do some writes while child is reading
      5.times do |i|
        writer_store.transaction_with_retry do
          writer_store.db[:facts].insert(
            subject_entity_id: entity_id,
            predicate: "write_#{i}",
            object_literal: "value",
            status: "active",
            confidence: 1.0,
            created_at: Time.now.utc.iso8601,
            scope: "project",
            docid: "wal_#{i}"
          )
        end
      end

      result = nil
      Timeout.timeout(5) do
        Process.wait(child_pid)
        result = reader_pipe.read.strip
      end
      reader_pipe.close

      expect(result).to start_with("success:"),
        "Reader process failed: #{result}"

      writer_store.close
    end

    it "handles WAL checkpoint during concurrent access" do
      setup_store = described_class.new(db_path)
      entity_id = setup_store.find_or_create_entity(type: "test", name: "project")
      setup_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test",
        object_literal: "value"
      )
      setup_store.close

      # One process checkpoints while another tries to connect
      checkpoint_store = described_class.new(db_path)

      reader, writer = IO.pipe

      pid = fork do
        reader.close
        sleep 0.01 # Let checkpoint start

        begin
          hook_store = described_class.new(db_path)
          count = hook_store.facts.count
          hook_store.close
          writer.puts "success:#{count}"
        rescue Sequel::DatabaseConnectionError, Sequel::DatabaseError, Extralite::Error => e
          writer.puts "error:#{e.class}:#{e.message}"
        ensure
          writer.close
        end
      end

      writer.close

      # Run checkpoint (can briefly lock database)
      checkpoint_store.checkpoint_wal

      result = nil
      Timeout.timeout(5) do
        Process.wait(pid)
        result = reader.read.strip
      end
      reader.close

      expect(result).to start_with("success:"),
        "Hook process failed during checkpoint: #{result}"

      checkpoint_store.close
    end
  end
end
