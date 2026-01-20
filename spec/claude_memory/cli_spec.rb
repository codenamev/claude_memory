# frozen_string_literal: true

require "stringio"

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
end
