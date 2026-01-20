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
end
