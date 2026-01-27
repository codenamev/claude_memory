# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Commands::DoctorCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:test_dir) { File.join(Dir.tmpdir, "doctor_test_#{Process.pid}") }

  before do
    FileUtils.mkdir_p(test_dir)
    FileUtils.mkdir_p(File.join(test_dir, ".claude"))
    FileUtils.mkdir_p(File.join(test_dir, ".claude", "rules"))
    Dir.chdir(test_dir)
  end

  after do
    Dir.chdir("/")  # Exit test directory before removing
    FileUtils.rm_rf(test_dir)
  end

  describe "#call" do
    context "with healthy system" do
      before do
        # Create databases
        manager = ClaudeMemory::Store::StoreManager.new(
          global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
          project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
        )
        manager.ensure_both!
        manager.close

        # Create snapshot
        File.write(".claude/rules/claude_memory.generated.md", "# Memory")

        # Create CLAUDE.md with import
        File.write(".claude/CLAUDE.md", "@.claude/rules/claude_memory.generated.md")

        # Create hooks config
        File.write(".claude/settings.json", JSON.generate({
          hooks: {
            "Stop" => [],
            "SessionStart" => [],
            "PreCompact" => [],
            "SessionEnd" => []
          }
        }))
      end

      it "returns exit code 0" do
        # Override database paths in command
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        exit_code = command.call([])
        expect(exit_code).to eq(0)
      end

      it "reports all checks passed" do
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        command.call([])
        expect(stdout.string).to include("All checks passed!")
      end

      it "displays database stats" do
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        command.call([])
        expect(stdout.string).to include("Facts:")
        expect(stdout.string).to include("Content items:")
        expect(stdout.string).to include("Open conflicts:")
      end
    end

    context "with missing global database" do
      it "returns exit code 1" do
        # No databases created
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        exit_code = command.call([])
        expect(exit_code).to eq(1)
      end

      it "reports issue" do
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        command.call([])
        expect(stderr.string).to include("Global database not found")
      end
    end

    context "with warnings" do
      before do
        # Create databases
        manager = ClaudeMemory::Store::StoreManager.new(
          global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
          project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
        )
        manager.ensure_both!
        manager.close

        # No snapshot or hooks - will generate warnings
      end

      it "returns exit code 0 with warnings" do
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        exit_code = command.call([])
        expect(exit_code).to eq(0)
      end

      it "displays warnings" do
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        command.call([])
        expect(stdout.string).to include("Warnings:")
        expect(stdout.string).to include("⚠")
      end
    end

    it "displays doctor header" do
      allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
        ClaudeMemory::Store::StoreManager.new(
          global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
          project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
        )
      )

      command.call([])
      expect(stdout.string).to include("Claude Memory Doctor")
    end

    context "with orphaned hooks (hooks without MCP configuration)" do
      before do
        # Create databases
        manager = ClaudeMemory::Store::StoreManager.new(
          global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
          project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
        )
        manager.ensure_both!
        manager.close

        # Create hooks but NO .claude.json MCP configuration
        File.write(".claude/settings.json", JSON.generate({
          hooks: {
            "Stop" => [{
              "hooks" => [
                {"type" => "command", "command" => "claude-memory hook ingest --db .claude/memory.sqlite3", "timeout" => 10}
              ]
            }]
          }
        }))

        # No .claude.json file - orphaned hooks
      end

      it "warns about orphaned hooks" do
        allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
          ClaudeMemory::Store::StoreManager.new(
            global_db_path: File.join(test_dir, ".claude", "global.sqlite3"),
            project_db_path: File.join(test_dir, ".claude", "memory.sqlite3")
          )
        )

        command.call([])
        expect(stdout.string).to include("Warnings:")
        expect(stdout.string).to include("Orphaned hooks detected")
        expect(stdout.string).to include("claude-memory uninstall")
      end
    end
  end
end
