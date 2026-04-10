# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::EmbeddingsCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:global_db_path) { File.join(Dir.tmpdir, "embed_cmd_global_#{Process.pid}.sqlite3") }
  let(:project_db_path) { File.join(Dir.tmpdir, "embed_cmd_project_#{Process.pid}.sqlite3") }

  before do
    config = instance_double(ClaudeMemory::Configuration,
      global_db_path: global_db_path,
      project_db_path: project_db_path)
    allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)
  end

  after do
    FileUtils.rm_f(global_db_path)
    FileUtils.rm_f(project_db_path)
  end

  describe "#call with no subcommand" do
    it "shows current configuration" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Embedding Configuration")
      expect(stdout.string).to include("Provider:")
      expect(stdout.string).to include("CLAUDE_MEMORY_EMBEDDING_PROVIDER")
    end

    it "shows database state when databases exist" do
      # Create a real database with embedding metadata
      store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      store.set_meta("embedding_provider", "tfidf")
      store.set_meta("embedding_dimensions", "384")
      store.close

      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Global DB:")
      expect(stdout.string).to include("provider=tfidf")
      expect(stdout.string).to include("dimensions=384")
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
      expect(stdout.string).to include("1536-dim")
    end
  end

  describe "#call with 'check'" do
    it "validates tfidf setup (always passes)" do
      exit_code = command.call(["check"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("tfidf provider")
      expect(stdout.string).to include("All checks passed")
    end

    it "detects dimension mismatch in existing database" do
      # Create a database with 768-dim embeddings (simulating a provider switch)
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.set_meta("embedding_dimensions", "768")
      store.set_meta("embedding_provider", "fastembed")
      store.close

      command.call(["check"])
      # tfidf default is 384 but DB has 768 → mismatch warning
      expect(stdout.string).to include("Dimension mismatch")
      expect(stdout.string).to include("stored: 768")
      expect(stdout.string).to include("current: 384")
    end

    it "reports OK when dimensions match" do
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.set_meta("embedding_dimensions", "384")
      store.set_meta("embedding_provider", "tfidf")
      store.close

      exit_code = command.call(["check"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("[OK] project: 384-dim")
    end
  end

  describe "store connection safety" do
    it "closes store even when check_dimension_compatibility raises" do
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.set_meta("embedding_dimensions", "384")
      store.close

      # Stub SQLiteStore.new to return a spy that tracks close calls
      spy_store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      allow(spy_store).to receive(:get_meta).and_call_original
      allow(spy_store).to receive(:get_meta).with("embedding_dimensions").and_raise(RuntimeError, "db error")
      allow(spy_store).to receive(:close).and_call_original
      allow(ClaudeMemory::Store::SQLiteStore).to receive(:new).with(project_db_path).and_return(spy_store)

      # The check subcommand should still close the store despite the error
      expect { command.call(["check"]) }.to raise_error(RuntimeError, "db error")
      expect(spy_store).to have_received(:close)
    end

    it "closes store even when show_database_state raises" do
      store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      store.set_meta("embedding_provider", "tfidf")
      store.close

      spy_store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      allow(spy_store).to receive(:get_meta).and_raise(RuntimeError, "db error")
      allow(spy_store).to receive(:close).and_call_original
      allow(ClaudeMemory::Store::SQLiteStore).to receive(:new).with(global_db_path).and_return(spy_store)

      expect { command.call([]) }.to raise_error(RuntimeError, "db error")
      expect(spy_store).to have_received(:close)
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
