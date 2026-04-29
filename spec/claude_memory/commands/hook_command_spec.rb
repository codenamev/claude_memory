# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "digest"

RSpec.describe ClaudeMemory::Commands::HookCommand do
  let(:tmpdir) { Dir.mktmpdir("hook_command_test_#{Process.pid}") }
  let(:db_path) { File.join(tmpdir, "test.sqlite3") }
  let(:transcript_path) { File.join(tmpdir, "transcript.txt") }
  let(:stdin) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdin: stdin, stdout: stdout, stderr: stderr) }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "exit codes" do
    describe "ingest subcommand" do
      it "returns SUCCESS (0) for successful ingest" do
        File.write(transcript_path, "Test content")

        payload = {
          "session_id" => "sess-123",
          "transcript_path" => transcript_path
        }
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["ingest", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      end

      it "returns SUCCESS (0) for no new content" do
        File.write(transcript_path, "Test content")

        # First ingest
        payload = {
          "session_id" => "sess-123",
          "transcript_path" => transcript_path
        }
        stdin.string = JSON.generate(payload)
        command.call(["ingest", "--db", db_path])

        # Second ingest with same content
        stdin2 = StringIO.new(JSON.generate(payload))
        command2 = described_class.new(stdin: stdin2, stdout: StringIO.new, stderr: StringIO.new)
        exit_code = command2.call(["ingest", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      end

      it "returns SUCCESS (0) for session excluded by privacy marker" do
        File.write(transcript_path, "Content <no-memory>DO NOT INDEX</no-memory> more")

        payload = {
          "session_id" => "sess-123",
          "transcript_path" => transcript_path
        }
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["ingest", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
        expect(stdout.string).to include("excluded")
      end

      it "returns WARNING (1) for skipped ingest (missing file)" do
        payload = {
          "session_id" => "sess-123",
          "transcript_path" => "/nonexistent/file.txt"
        }
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["ingest", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::WARNING)
      end

      it "returns ERROR (2) for invalid JSON payload" do
        stdin.string = "invalid json{{"

        exit_code = command.call(["ingest", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
      end

      it "returns ERROR (2) for missing required payload fields" do
        payload = {
          "session_id" => "sess-123"
          # Missing transcript_path
        }
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["ingest", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
      end
    end

    describe "sweep subcommand" do
      it "returns SUCCESS (0) for successful sweep" do
        payload = {
          "budget_seconds" => 2
        }
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["sweep", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      end

      it "returns ERROR (2) for invalid JSON payload" do
        stdin.string = "not json"

        exit_code = command.call(["sweep", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
      end
    end

    describe "publish subcommand" do
      it "returns SUCCESS (0) for successful publish" do
        rules_dir = File.join(tmpdir, ".claude", "rules")
        FileUtils.mkdir_p(rules_dir)

        payload = {
          "rules_dir" => rules_dir,
          "mode" => "shared"
        }
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["publish", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      end
    end

    describe "context subcommand" do
      it "returns SUCCESS (0) for context query" do
        payload = {"hook_event_name" => "SessionStart"}
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["context", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      end

      it "outputs JSON with hookSpecificOutput when facts exist" do
        # Create a fact first
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        text = "decision constraint Use Docker for deployment"
        content_id = store.upsert_content_item(
          source: "test",
          session_id: "sess-1",
          text_hash: Digest::SHA256.hexdigest(text),
          byte_len: text.bytesize,
          raw_text: text
        )
        fts = ClaudeMemory::Index::LexicalFTS.new(store)
        fts.index_content_item(content_id, text)
        entity_id = store.find_or_create_entity(type: "repo", name: "myapp")
        fact_id = store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "decision",
          object_literal: "Use Docker for deployment",
          status: "active",
          scope: "project"
        )
        store.insert_provenance(
          fact_id: fact_id,
          content_item_id: content_id,
          quote: text,
          strength: "stated"
        )
        store.close

        payload = {"hook_event_name" => "SessionStart"}
        stdin.string = JSON.generate(payload)

        exit_code = command.call(["context", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
        output = JSON.parse(stdout.string)
        expect(output.dig("hookSpecificOutput", "hookEventName")).to eq("SessionStart")
        expect(output.dig("hookSpecificOutput", "additionalContext")).to include("Docker")
      end

      it "records context_tokens on the activity event" do
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        text = "decision constraint Use Docker for deployment"
        content_id = store.upsert_content_item(
          source: "test", session_id: "sess-1",
          text_hash: Digest::SHA256.hexdigest(text),
          byte_len: text.bytesize, raw_text: text
        )
        ClaudeMemory::Index::LexicalFTS.new(store).index_content_item(content_id, text)
        entity_id = store.find_or_create_entity(type: "repo", name: "myapp")
        fact_id = store.insert_fact(
          subject_entity_id: entity_id, predicate: "decision",
          object_literal: "Use Docker for deployment",
          status: "active", scope: "project"
        )
        store.insert_provenance(
          fact_id: fact_id, content_item_id: content_id,
          quote: text, strength: "stated"
        )
        store.close

        payload = {"hook_event_name" => "SessionStart"}
        stdin.string = JSON.generate(payload)
        command.call(["context", "--db", db_path])

        check_store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        event = check_store.activity_events.where(event_type: "hook_context").order(:id).last
        details = JSON.parse(event[:detail_json])
        check_store.close

        expect(details["context_tokens"]).to be_a(Integer)
        expect(details["context_tokens"]).to be > 0
        expect(details["context_length"]).to be > 0
      end

      it "outputs nothing when no facts exist" do
        payload = {"hook_event_name" => "SessionStart"}
        stdin.string = JSON.generate(payload)

        # Isolate from real global database
        empty_global = File.join(tmpdir, "empty_global.sqlite3")
        config = instance_double(
          ClaudeMemory::Configuration,
          global_db_path: empty_global,
          project_db_path: db_path,
          project_dir: tmpdir,
          claude_config_dir: File.join(tmpdir, "claude_config")
        )
        allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)

        exit_code = command.call(["context", "--db", db_path])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
        expect(stdout.string.strip).to be_empty
      end
    end

    describe "unknown subcommand" do
      it "returns ERROR (2) for unknown subcommand" do
        exit_code = command.call(["unknown"])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
        expect(stderr.string).to include("Unknown hook command")
      end
    end

    describe "missing subcommand" do
      it "returns ERROR (2) when no subcommand provided" do
        exit_code = command.call([])

        expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
        expect(stderr.string).to include("Usage")
      end
    end
  end

  describe "error classification" do
    it "returns SUCCESS (0) for database errors (transport failure)" do
      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }
      stdin.string = JSON.generate(payload)

      # Simulate database error by using an invalid path that causes Sequel error
      allow(ClaudeMemory::Store::SQLiteStore).to receive(:new)
        .and_raise(Sequel::DatabaseConnectionError.new("unable to open database"))

      exit_code = command.call(["ingest", "--db", "/invalid/path/db.sqlite3"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stderr.string).to include("degraded gracefully")
    end

    it "returns SUCCESS (0) for permission errors (transport failure)" do
      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }
      stdin.string = JSON.generate(payload)

      allow(ClaudeMemory::Store::SQLiteStore).to receive(:new)
        .and_raise(Errno::EACCES.new("permission denied"))

      exit_code = command.call(["ingest", "--db", db_path])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stderr.string).to include("degraded gracefully")
    end

    it "returns ERROR (2) for PayloadError (client bug)" do
      payload = {
        "session_id" => "sess-123"
        # Missing transcript_path
      }
      stdin.string = JSON.generate(payload)

      exit_code = command.call(["ingest", "--db", db_path])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
    end

    it "returns SUCCESS (0) for context hook with database errors" do
      payload = {"hook_event_name" => "SessionStart"}
      stdin.string = JSON.generate(payload)

      allow(ClaudeMemory::Store::StoreManager).to receive(:new)
        .and_raise(Sequel::DatabaseError.new("database is locked"))

      exit_code = command.call(["context", "--db", db_path])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stderr.string).to include("degraded gracefully")
    end

    it "returns SUCCESS (0) for unexpected RuntimeError (graceful degradation)" do
      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }
      stdin.string = JSON.generate(payload)

      allow(ClaudeMemory::Store::SQLiteStore).to receive(:new)
        .and_raise(RuntimeError.new("something unexpected"))

      exit_code = command.call(["ingest", "--db", db_path])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stderr.string).to include("degraded gracefully")
    end
  end

  describe "output messages" do
    it "prints success message for ingested content" do
      File.write(transcript_path, "New content")

      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }
      stdin.string = JSON.generate(payload)

      command.call(["ingest", "--db", db_path])

      expect(stdout.string).to include("Ingested")
      expect(stdout.string).to include("bytes")
    end

    it "prints message for no new content" do
      File.write(transcript_path, "Content")

      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }

      # First ingest
      stdin.string = JSON.generate(payload)
      command.call(["ingest", "--db", db_path])

      # Second ingest
      stdin2 = StringIO.new(JSON.generate(payload))
      stdout2 = StringIO.new
      command2 = described_class.new(stdin: stdin2, stdout: stdout2, stderr: StringIO.new)
      command2.call(["ingest", "--db", db_path])

      expect(stdout2.string).to include("No new content")
    end

    it "prints message for skipped ingest" do
      payload = {
        "session_id" => "sess-123",
        "transcript_path" => "/nonexistent/file.txt"
      }
      stdin.string = JSON.generate(payload)

      command.call(["ingest", "--db", db_path])

      expect(stdout.string).to include("Skipped")
    end
  end

  describe "--async flag" do
    it "returns SUCCESS immediately with --async for ingest" do
      File.write(transcript_path, "Test content")

      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }
      stdin.string = JSON.generate(payload)

      allow(Process).to receive(:fork).and_return(42)
      allow(Process).to receive(:detach)

      exit_code = command.call(["ingest", "--db", db_path, "--async"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stdout.string).to include("background")
      expect(stdout.string).to include("42")
      expect(Process).to have_received(:detach).with(42)
    end

    it "returns SUCCESS immediately with --async for sweep" do
      payload = {"budget_seconds" => 2}
      stdin.string = JSON.generate(payload)

      allow(Process).to receive(:fork).and_return(99)
      allow(Process).to receive(:detach)

      exit_code = command.call(["sweep", "--db", db_path, "--async"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stdout.string).to include("background")
    end

    it "returns SUCCESS immediately with --async for publish" do
      rules_dir = File.join(tmpdir, ".claude", "rules")
      FileUtils.mkdir_p(rules_dir)

      payload = {"rules_dir" => rules_dir, "mode" => "shared"}
      stdin.string = JSON.generate(payload)

      allow(Process).to receive(:fork).and_return(77)
      allow(Process).to receive(:detach)

      exit_code = command.call(["publish", "--db", db_path, "--async"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stdout.string).to include("background")
    end

    it "ignores --async for context subcommand (runs synchronously)" do
      payload = {"hook_event_name" => "SessionStart"}
      stdin.string = JSON.generate(payload)

      exit_code = command.call(["context", "--db", db_path, "--async"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      # Context runs synchronously even with --async
      expect(stdout.string).not_to include("background")
    end

    it "falls back to synchronous execution when fork is unavailable" do
      File.write(transcript_path, "Test content")

      payload = {
        "session_id" => "sess-123",
        "transcript_path" => transcript_path
      }
      stdin.string = JSON.generate(payload)

      allow(Process).to receive(:fork).and_raise(NotImplementedError)

      exit_code = command.call(["ingest", "--db", db_path, "--async"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
      expect(stderr.string).to include("falling back")
      expect(stdout.string).to include("Ingested")
    end

    it "still returns ERROR for invalid payload with --async" do
      stdin.string = "invalid json{{"

      exit_code = command.call(["ingest", "--db", db_path, "--async"])

      expect(exit_code).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
    end
  end
end
