# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::CompactCommand do
  let(:tmpdir) { Dir.mktmpdir("compact_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  before do
    # Create databases with some data to make VACUUM meaningful
    allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
      instance_double(
        ClaudeMemory::Store::StoreManager,
        global_db_path: global_db_path,
        project_db_path: project_db_path,
        close: nil
      )
    )
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def create_database(path)
    store = ClaudeMemory::Store::SQLiteStore.new(path)
    entity_id = store.find_or_create_entity(type: "repo", name: "test")
    10.times do |i|
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "Rule #{i} " * 50
      )
    end
    store.close
  end

  describe "compacting databases" do
    it "compacts both databases with default scope" do
      create_database(global_db_path)
      create_database(project_db_path)

      exit_code = command.call([])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("global: compacting...")
      expect(stdout.string).to include("project: compacting...")
      expect(stdout.string).to include("->")
    end

    it "compacts only global database with --scope global" do
      create_database(global_db_path)
      create_database(project_db_path)

      exit_code = command.call(["--scope", "global"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("global: compacting...")
      expect(stdout.string).not_to include("project: compacting...")
    end

    it "compacts only project database with --scope project" do
      create_database(global_db_path)
      create_database(project_db_path)

      exit_code = command.call(["--scope", "project"])

      expect(exit_code).to eq(0)
      expect(stdout.string).not_to include("global: compacting...")
      expect(stdout.string).to include("project: compacting...")
    end

    it "reports when database does not exist" do
      exit_code = command.call(["--scope", "global"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("not found")
    end

    it "shows size before and after" do
      create_database(global_db_path)

      exit_code = command.call(["--scope", "global"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to match(/\d+(\.\d+)?\s*(KB|MB)\s*->\s*\d+(\.\d+)?\s*(KB|MB)/)
    end
  end

  describe "--check flag" do
    it "runs integrity check before compacting" do
      create_database(global_db_path)

      exit_code = command.call(["--scope", "global", "--check"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("integrity check passed")
      expect(stdout.string).to include("compacting...")
    end

    it "skips compacting if integrity check fails" do
      create_database(global_db_path)

      # Corrupt a small amount of data to trigger integrity failure
      # We mock this since real corruption is hard to produce
      allow_any_instance_of(described_class).to receive(:run_integrity_check)
        .and_return("corruption found on page 5")

      exit_code = command.call(["--scope", "global", "--check"])

      expect(exit_code).to eq(0)
      expect(stderr.string).to include("integrity check failed")
      expect(stdout.string).not_to include("compacting...")
    end
  end
end
