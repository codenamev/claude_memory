# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "stringio"

RSpec.describe ClaudeMemory::Commands::SetupVectorsCommand do
  let(:tmpdir) { Dir.mktmpdir("setup_vectors_spec") }
  let(:claude_dir) { File.join(tmpdir, ".claude") }
  let(:settings_path) { File.join(claude_dir, "settings.json") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    FileUtils.mkdir_p(claude_dir)
    config = instance_double(
      ClaudeMemory::Configuration,
      project_dir: tmpdir,
      project_db_path: File.join(claude_dir, "memory.sqlite3"),
      global_db_path: File.join(claude_dir, "global.sqlite3"),
      claude_config_dir: claude_dir
    )
    allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "--dry-run" do
    it "does not write settings.json" do
      exit_code = command.call(["--dry-run", "--provider=tfidf"])
      expect(exit_code).to eq(0)
      expect(File.exist?(settings_path)).to be(false)
      expect(stdout.string).to include("Would write")
    end
  end

  describe "writing settings.json" do
    it "writes provider env to a fresh settings file" do
      command.call(["--provider=tfidf", "--no-reindex"])
      payload = JSON.parse(File.read(settings_path))
      expect(payload["env"]["CLAUDE_MEMORY_EMBEDDING_PROVIDER"]).to eq("tfidf")
    end

    it "writes provider AND model when --model is given" do
      command.call(["--provider=tfidf", "--model=BAAI/bge-small-en-v1.5", "--no-reindex"])
      env = JSON.parse(File.read(settings_path))["env"]
      expect(env["CLAUDE_MEMORY_EMBEDDING_PROVIDER"]).to eq("tfidf")
      expect(env["CLAUDE_MEMORY_EMBEDDING_MODEL"]).to eq("BAAI/bge-small-en-v1.5")
    end

    it "preserves unrelated keys in settings.json" do
      File.write(settings_path, JSON.pretty_generate({
        "env" => {"UNRELATED" => "preserved"},
        "permissions" => ["something"]
      }))
      command.call(["--provider=tfidf", "--no-reindex"])
      settings = JSON.parse(File.read(settings_path))
      expect(settings["env"]["UNRELATED"]).to eq("preserved")
      expect(settings["env"]["CLAUDE_MEMORY_EMBEDDING_PROVIDER"]).to eq("tfidf")
      expect(settings["permissions"]).to eq(["something"])
    end

    it "clears the model key when --model is omitted on a subsequent run" do
      File.write(settings_path, JSON.pretty_generate({
        "env" => {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "old-model"}
      }))
      command.call(["--provider=tfidf", "--no-reindex"])
      env = JSON.parse(File.read(settings_path))["env"]
      expect(env).not_to have_key("CLAUDE_MEMORY_EMBEDDING_MODEL")
    end
  end

  describe "--status" do
    it "reports default tfidf when nothing is configured" do
      command.call(["--status"])
      expect(stdout.string).to include("Current provider:")
      expect(stdout.string).to include("none — using default tfidf")
    end

    it "lists configured env vars when present" do
      File.write(settings_path, JSON.pretty_generate({
        "env" => {"CLAUDE_MEMORY_EMBEDDING_PROVIDER" => "fastembed"}
      }))
      command.call(["--status"])
      expect(stdout.string).to include("CLAUDE_MEMORY_EMBEDDING_PROVIDER=fastembed")
    end
  end

  describe "invalid provider" do
    it "exits 1 and does not write settings.json" do
      exit_code = command.call(["--provider=bogus", "--dry-run"])
      expect(exit_code).to eq(1)
      expect(stderr.string).to include("Unknown provider")
      expect(File.exist?(settings_path)).to be(false)
    end
  end
end
