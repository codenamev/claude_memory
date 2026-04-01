# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe ClaudeMemory::Commands::EmbeddingsCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  # Prevent database access in tests by making paths point to nonexistent dirs
  before do
    tmpdir = Dir.mktmpdir("embeddings_cmd_test")
    config = instance_double(ClaudeMemory::Configuration,
      global_db_path: File.join(tmpdir, "nonexistent", "global.sqlite3"),
      project_db_path: File.join(tmpdir, "nonexistent", "project.sqlite3"))
    allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)
  end

  describe "#call with no subcommand" do
    it "shows current configuration" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Embedding Configuration")
      expect(stdout.string).to include("Provider:")
      expect(stdout.string).to include("CLAUDE_MEMORY_EMBEDDING_PROVIDER")
    end
  end

  describe "#call with 'list'" do
    it "lists available models by provider" do
      exit_code = command.call(["list"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("fastembed")
      expect(stdout.string).to include("api")
      expect(stdout.string).to include("tfidf")
      expect(stdout.string).to include("BAAI/bge-small-en-v1.5")
      expect(stdout.string).to include("text-embedding-3-small")
      expect(stdout.string).to include("384-dim")
    end
  end

  describe "#call with 'check'" do
    it "validates tfidf setup (always passes)" do
      exit_code = command.call(["check"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("tfidf provider")
      expect(stdout.string).to include("All checks passed")
    end
  end

  describe "#call with unknown subcommand" do
    it "returns error" do
      exit_code = command.call(["bogus"])
      expect(exit_code).to eq(1)
      expect(stderr.string).to include("Unknown subcommand: bogus")
    end
  end
end
