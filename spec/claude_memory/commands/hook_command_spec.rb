# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

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
end
