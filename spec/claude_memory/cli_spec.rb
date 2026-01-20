# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  def run_cli(*args)
    described_class.new(args, stdout: stdout, stderr: stderr).run
  end

  describe "help command" do
    it "prints help with 'help' command" do
      expect(run_cli("help")).to eq(0)
      expect(stdout.string).to include("claude-memory")
      expect(stdout.string).to include("Commands:")
    end

    it "prints help with --help flag" do
      expect(run_cli("--help")).to eq(0)
      expect(stdout.string).to include("claude-memory")
    end

    it "prints help with -h flag" do
      expect(run_cli("-h")).to eq(0)
      expect(stdout.string).to include("claude-memory")
    end

    it "prints help when no command given" do
      expect(run_cli).to eq(0)
      expect(stdout.string).to include("claude-memory")
    end
  end

  describe "version command" do
    it "prints version with 'version' command" do
      expect(run_cli("version")).to eq(0)
      expect(stdout.string).to include(ClaudeMemory::VERSION)
    end

    it "prints version with --version flag" do
      expect(run_cli("--version")).to eq(0)
      expect(stdout.string).to include(ClaudeMemory::VERSION)
    end

    it "prints version with -v flag" do
      expect(run_cli("-v")).to eq(0)
      expect(stdout.string).to include(ClaudeMemory::VERSION)
    end
  end

  describe "unknown command" do
    it "returns error code and prints message" do
      expect(run_cli("unknown")).to eq(1)
      expect(stderr.string).to include("Unknown command: unknown")
    end
  end

  describe "db:init command" do
    let(:db_path) { File.join(Dir.tmpdir, "cli_test_#{Process.pid}.sqlite3") }

    after { FileUtils.rm_f(db_path) }

    it "creates the database file" do
      expect(run_cli("db:init", db_path)).to eq(0)
      expect(File.exist?(db_path)).to be true
      expect(stdout.string).to include("Database initialized")
      expect(stdout.string).to include("Schema version: 1")
    end

    it "is idempotent" do
      run_cli("db:init", db_path)
      stdout.truncate(0)
      stdout.rewind
      expect(run_cli("db:init", db_path)).to eq(0)
      expect(stdout.string).to include("Database initialized")
    end
  end

  describe "ingest command" do
    let(:db_path) { File.join(Dir.tmpdir, "cli_ingest_test_#{Process.pid}.sqlite3") }
    let(:transcript_path) { File.join(Dir.tmpdir, "transcript_cli_#{Process.pid}.jsonl") }

    before { File.write(transcript_path, "some content\n") }

    after do
      FileUtils.rm_f(db_path)
      FileUtils.rm_f(transcript_path)
    end

    it "requires session-id and transcript-path" do
      expect(run_cli("ingest")).to eq(1)
      expect(stderr.string).to include("--session-id")
      expect(stderr.string).to include("--transcript-path")
    end

    it "ingests content" do
      code = run_cli("ingest", "--session-id", "sess-1", "--transcript-path", transcript_path, "--db", db_path)
      expect(code).to eq(0)
      expect(stdout.string).to include("Ingested")
      expect(stdout.string).to include("13 bytes")
    end

    it "reports no change on second run" do
      run_cli("ingest", "--session-id", "sess-1", "--transcript-path", transcript_path, "--db", db_path)
      stdout.truncate(0)
      stdout.rewind

      code = run_cli("ingest", "--session-id", "sess-1", "--transcript-path", transcript_path, "--db", db_path)
      expect(code).to eq(0)
      expect(stdout.string).to include("No new content")
    end

    it "handles missing file" do
      FileUtils.rm_f(transcript_path)
      code = run_cli("ingest", "--session-id", "sess-1", "--transcript-path", transcript_path, "--db", db_path)
      expect(code).to eq(1)
      expect(stderr.string).to include("File not found")
    end
  end

  describe "search command" do
    let(:db_path) { File.join(Dir.tmpdir, "cli_search_test_#{Process.pid}.sqlite3") }
    let(:transcript_path) { File.join(Dir.tmpdir, "transcript_search_#{Process.pid}.jsonl") }

    before do
      File.write(transcript_path, "We are using PostgreSQL for our database.\n")
      run_cli("ingest", "--session-id", "sess-1", "--transcript-path", transcript_path, "--db", db_path)
      stdout.truncate(0)
      stdout.rewind
    end

    after do
      FileUtils.rm_f(db_path)
      FileUtils.rm_f(transcript_path)
    end

    it "requires a query" do
      expect(run_cli("search")).to eq(1)
      expect(stderr.string).to include("Usage:")
    end

    it "finds matching content" do
      code = run_cli("search", "PostgreSQL", "--db", db_path)
      expect(code).to eq(0)
      expect(stdout.string).to include("Found 1 result")
      expect(stdout.string).to include("PostgreSQL")
    end

    it "reports no results" do
      code = run_cli("search", "MongoDB", "--db", db_path)
      expect(code).to eq(0)
      expect(stdout.string).to include("No results found")
    end
  end

  describe "hook command" do
    let(:db_path) { File.join(Dir.tmpdir, "cli_hook_test_#{Process.pid}.sqlite3") }
    let(:transcript_path) { File.join(Dir.tmpdir, "hook_transcript_#{Process.pid}.jsonl") }
    let(:stdin) { StringIO.new }

    def run_cli_with_stdin(*args, input:)
      described_class.new(args, stdout: stdout, stderr: stderr, stdin: StringIO.new(input)).run
    end

    before { File.write(transcript_path, "hook test content\n") }

    after do
      FileUtils.rm_f(db_path)
      FileUtils.rm_f(transcript_path)
    end

    describe "hook ingest" do
      it "ingests from stdin JSON payload" do
        payload = {
          "session_id" => "hook-session-1",
          "transcript_path" => transcript_path
        }.to_json

        code = run_cli_with_stdin("hook", "ingest", "--db", db_path, input: payload)

        expect(code).to eq(0)
        expect(stdout.string).to include("Ingested")
      end

      it "reports error for invalid payload" do
        code = run_cli_with_stdin("hook", "ingest", "--db", db_path, input: "{}")

        expect(code).to eq(1)
        expect(stderr.string).to include("session_id")
      end

      it "handles invalid JSON" do
        code = run_cli_with_stdin("hook", "ingest", "--db", db_path, input: "not json")

        expect(code).to eq(1)
        expect(stderr.string).to include("Invalid JSON")
      end
    end

    describe "hook sweep" do
      before do
        ClaudeMemory::Store::SQLiteStore.new(db_path).close
      end

      it "runs sweep from stdin JSON payload" do
        payload = {"budget" => 1}.to_json

        code = run_cli_with_stdin("hook", "sweep", "--db", db_path, input: payload)

        expect(code).to eq(0)
        expect(stdout.string).to include("Sweep complete")
      end

      it "accepts empty payload" do
        code = run_cli_with_stdin("hook", "sweep", "--db", db_path, input: "{}")

        expect(code).to eq(0)
        expect(stdout.string).to include("Sweep complete")
      end
    end

    describe "hook publish" do
      let(:project_dir) { Dir.mktmpdir("cli_hook_publish_#{Process.pid}") }

      before do
        @original_dir = Dir.pwd
        Dir.chdir(project_dir)
        ClaudeMemory::Store::SQLiteStore.new(db_path).close
      end

      after do
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(project_dir)
      end

      it "publishes snapshot from stdin JSON payload" do
        payload = {"mode" => "shared"}.to_json

        code = run_cli_with_stdin("hook", "publish", "--db", db_path, input: payload)

        expect(code).to eq(0)
        expect(stdout.string).to match(/Published|unchanged/)
      end
    end

    it "shows help for unknown hook subcommand" do
      code = run_cli_with_stdin("hook", "unknown", input: "{}")

      expect(code).to eq(1)
      expect(stderr.string).to include("Unknown hook command")
    end

    it "shows help when no subcommand given" do
      code = run_cli_with_stdin("hook", input: "")

      expect(code).to eq(1)
      expect(stderr.string).to include("Usage:")
    end
  end

  describe "init command" do
    describe "with --global flag" do
      let(:fake_home) { Dir.mktmpdir("cli_init_global_#{Process.pid}") }

      before do
        @original_home = ENV["HOME"]
        ENV["HOME"] = fake_home
      end

      after do
        ENV["HOME"] = @original_home
        FileUtils.rm_rf(fake_home)
      end

      it "creates global database in ~/.claude/" do
        code = run_cli("init", "--global")

        expect(code).to eq(0)
        expect(stdout.string).to include("global")
        expect(File.exist?(File.join(fake_home, ".claude", "claude_memory.sqlite3"))).to be true
      end

      it "configures hooks in ~/.claude/settings.json" do
        run_cli("init", "--global")

        settings_path = File.join(fake_home, ".claude", "settings.json")
        expect(File.exist?(settings_path)).to be true

        config = JSON.parse(File.read(settings_path))
        expect(config["hooks"]).to include("Stop", "SessionStart")
      end

      it "configures MCP in ~/.claude.json" do
        run_cli("init", "--global")

        mcp_path = File.join(fake_home, ".claude.json")
        expect(File.exist?(mcp_path)).to be true

        config = JSON.parse(File.read(mcp_path))
        expect(config["mcpServers"]["claude-memory"]).to be_a(Hash)
      end

      it "creates or updates ~/.claude/CLAUDE.md" do
        run_cli("init", "--global")

        claude_md = File.join(fake_home, ".claude", "CLAUDE.md")
        expect(File.exist?(claude_md)).to be true
        expect(File.read(claude_md)).to include("ClaudeMemory")
      end
    end
  end
end
