# frozen_string_literal: true

require "stringio"

RSpec.describe ClaudeMemory::Commands::HelpCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  describe "#call" do
    it "prints help message to stdout" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("claude-memory - Long-term memory for Claude Code")
      expect(stdout.string).to include("Usage: claude-memory <command> [options]")
    end

    it "lists all available commands" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)

      # Check for key commands
      expect(stdout.string).to include("changes")
      expect(stdout.string).to include("conflicts")
      expect(stdout.string).to include("db:init")
      expect(stdout.string).to include("doctor")
      expect(stdout.string).to include("explain")
      expect(stdout.string).to include("help")
      expect(stdout.string).to include("hook")
      expect(stdout.string).to include("init")
      expect(stdout.string).to include("ingest")
      expect(stdout.string).to include("promote")
      expect(stdout.string).to include("publish")
      expect(stdout.string).to include("recall")
      expect(stdout.string).to include("search")
      expect(stdout.string).to include("serve-mcp")
      expect(stdout.string).to include("sweep")
      expect(stdout.string).to include("version")
    end

    it "includes command descriptions" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)

      expect(stdout.string).to include("Show recent fact changes")
      expect(stdout.string).to include("Show open conflicts")
      expect(stdout.string).to include("Initialize the SQLite database")
      expect(stdout.string).to include("Check system health")
      expect(stdout.string).to include("Recall facts matching a query")
    end

    it "writes nothing to stderr" do
      command.call([])
      expect(stderr.string).to be_empty
    end

    it "returns exit code 0" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
    end

    it "ignores any arguments passed" do
      exit_code = command.call(["--foo", "bar", "baz"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("claude-memory - Long-term memory")
    end

    it "includes footer with per-command help" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Run 'claude-memory <command> --help' for more information")
    end
  end
end
