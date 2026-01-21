# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::PromoteCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:test_dir) { File.join(Dir.tmpdir, "promote_test_#{Process.pid}") }

  before do
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#call" do
    context "with valid fact ID" do
      it "promotes fact and returns exit code 0" do
        # Setup test databases
        manager = ClaudeMemory::Store::StoreManager.new(
          global_db_path: File.join(test_dir, "global.sqlite3"),
          project_db_path: File.join(test_dir, "project.sqlite3"),
          project_path: test_dir
        )
        manager.ensure_both!

        # Create a project fact
        subject_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
        fact_id = manager.project_store.insert_fact(
          subject_entity_id: subject_id,
          predicate: "convention",
          object_literal: "test value",
          scope: "project",
          project_path: test_dir
        )
        manager.close

        # Mock StoreManager to use test databases
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, "global.sqlite3"),
            project_db_path: File.join(test_dir, "project.sqlite3"),
            project_path: test_dir
          )
        )

        exit_code = command.call([fact_id.to_s])
        expect(exit_code).to eq(0)
        expect(stdout.string).to include("Promoted fact ##{fact_id}")
      end
    end

    context "with missing fact ID" do
      it "returns exit code 1" do
        exit_code = command.call([])
        expect(exit_code).to eq(1)
        expect(stderr.string).to include("Usage:")
      end
    end

    context "with invalid fact ID" do
      it "shows usage for non-numeric ID" do
        exit_code = command.call(["abc"])
        expect(exit_code).to eq(1)
        expect(stderr.string).to include("Usage:")
      end

      it "shows usage for zero" do
        exit_code = command.call(["0"])
        expect(exit_code).to eq(1)
        expect(stderr.string).to include("Usage:")
      end
    end

    context "with non-existent fact" do
      it "returns exit code 1 and shows error" do
        manager = ClaudeMemory::Store::StoreManager.new(
          global_db_path: File.join(test_dir, "global.sqlite3"),
          project_db_path: File.join(test_dir, "project.sqlite3"),
          project_path: test_dir
        )
        manager.ensure_both!
        manager.close

        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, "global.sqlite3"),
            project_db_path: File.join(test_dir, "project.sqlite3"),
            project_path: test_dir
          )
        )

        exit_code = command.call(["999"])
        expect(exit_code).to eq(1)
        expect(stderr.string).to include("not found")
      end
    end
  end
end
