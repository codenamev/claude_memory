# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe ClaudeMemory::Commands::UninstallCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:stdin) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr, stdin: stdin) }

  around do |example|
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p(".claude/rules")
        example.run
      end
    end
  end

  describe "#call (local)" do
    let(:settings_path) { ".claude/settings.json" }
    let(:mcp_path) { ".claude.json" }
    let(:claude_md_path) { ".claude/CLAUDE.md" }

    before do
      # Set up sample configuration files
      FileUtils.mkdir_p(".claude")

      # Create settings.json with claude-memory hooks
      settings = {
        "hooks" => {
          "Stop" => [{
            "hooks" => [
              {"type" => "command", "command" => "claude-memory hook ingest --db .claude/memory.sqlite3", "timeout" => 10}
            ]
          }],
          "SessionStart" => [{
            "hooks" => [
              {"type" => "command", "command" => "claude-memory hook ingest --db .claude/memory.sqlite3", "timeout" => 10}
            ]
          }]
        }
      }
      File.write(settings_path, JSON.pretty_generate(settings))

      # Create .claude.json with MCP server
      mcp_config = {
        "mcpServers" => {
          "claude-memory" => {
            "type" => "stdio",
            "command" => "claude-memory",
            "args" => ["serve-mcp"]
          }
        }
      }
      File.write(mcp_path, JSON.pretty_generate(mcp_config))

      # Create CLAUDE.md with ClaudeMemory section
      claude_md = <<~MD
        <!-- ClaudeMemory v0.1.0 -->
        # ClaudeMemory

        This project has ClaudeMemory enabled.

        ## Other Section

        Some other content.
      MD
      File.write(claude_md_path, claude_md)

      # Create database and generated files
      File.write(".claude/memory.sqlite3", "fake db")
      File.write(".claude/rules/claude_memory.generated.md", "# Generated")
      FileUtils.mkdir_p(".claude/output_styles")
      File.write(".claude/output_styles/claude_memory.json", "{}")
    end

    context "without --full flag" do
      it "removes hooks, MCP server, and CLAUDE.md section but keeps database" do
        result = command.call([])

        expect(result).to eq(0)
        expect(stdout.string).to include("Uninstalling ClaudeMemory (project-local)")
        expect(stdout.string).to include("Hooks from .claude/settings.json")
        expect(stdout.string).to include("MCP server from .claude.json")
        expect(stdout.string).to include("ClaudeMemory section from .claude/CLAUDE.md")

        # Check hooks removed (key should be deleted entirely)
        settings = JSON.parse(File.read(settings_path))
        expect(settings["hooks"]).to be_nil

        # Check MCP removed
        mcp = JSON.parse(File.read(mcp_path))
        expect(mcp["mcpServers"]).to be_nil

        # Check CLAUDE.md section removed
        claude_md = File.read(claude_md_path)
        expect(claude_md).not_to include("ClaudeMemory")
        expect(claude_md).to include("## Other Section")

        # Database should still exist
        expect(File.exist?(".claude/memory.sqlite3")).to be true
      end
    end

    context "with --full flag" do
      it "removes all configuration including database and generated files" do
        result = command.call(["--full"])

        expect(result).to eq(0)
        expect(stdout.string).to include("Removed .claude/memory.sqlite3")
        expect(stdout.string).to include("Removed .claude/rules/claude_memory.generated.md")

        # All files should be removed
        expect(File.exist?(".claude/memory.sqlite3")).to be false
        expect(File.exist?(".claude/rules/claude_memory.generated.md")).to be false
        expect(File.exist?(".claude/output_styles/claude_memory.json")).to be false
      end
    end

    context "when no configuration exists" do
      before do
        FileUtils.rm_rf(".claude")
        FileUtils.rm_f(".claude.json")
      end

      it "reports nothing to remove" do
        result = command.call([])

        expect(result).to eq(0)
        expect(stdout.string).to include("No ClaudeMemory configuration found")
      end
    end
  end

  describe "#call (global)" do
    let(:home_dir) { Dir.pwd }

    before do
      allow(Dir).to receive(:home).and_return(home_dir)

      # Stub ClaudeMemory.global_db_path to use test directory
      test_global_db = File.join(home_dir, ".claude", "memory.sqlite3")
      allow(ClaudeMemory).to receive(:global_db_path).and_return(test_global_db)

      # Set up global configuration
      FileUtils.mkdir_p(".claude")

      settings = {
        "hooks" => {
          "Stop" => [{
            "hooks" => [
              {"type" => "command", "command" => "claude-memory hook ingest --db ~/.claude/memory.sqlite3", "timeout" => 10}
            ]
          }]
        }
      }
      File.write(".claude/settings.json", JSON.pretty_generate(settings))

      mcp_config = {
        "mcpServers" => {
          "claude-memory" => {
            "type" => "stdio",
            "command" => "claude-memory",
            "args" => ["serve-mcp"]
          }
        }
      }
      File.write(".claude.json", JSON.pretty_generate(mcp_config))

      # Create global database
      File.write(".claude/memory.sqlite3", "fake global db")
    end

    context "without --full flag" do
      it "removes global hooks and MCP but keeps database" do
        result = command.call(["--global"])

        expect(result).to eq(0)
        expect(stdout.string).to include("Uninstalling ClaudeMemory (global)")

        # Database should still exist
        expect(File.exist?(".claude/memory.sqlite3")).to be true
      end
    end

    context "with --full flag" do
      it "removes all global configuration including database" do
        result = command.call(["--global", "--full"])

        expect(result).to eq(0)
        expect(stdout.string).to include("Removed")
        expect(stdout.string).to include("memory.sqlite3")

        # Database should be removed
        expect(File.exist?(".claude/memory.sqlite3")).to be false
      end
    end
  end

  describe "#remove_hooks_from_file" do
    let(:settings_path) { ".claude/settings.json" }

    before do
      FileUtils.mkdir_p(".claude")
    end

    it "removes only claude-memory hooks, preserving other hooks" do
      settings = {
        "hooks" => {
          "Stop" => [
            {
              "hooks" => [
                {"type" => "command", "command" => "claude-memory hook ingest", "timeout" => 10}
              ]
            },
            {
              "hooks" => [
                {"type" => "command", "command" => "some-other-command", "timeout" => 10}
              ]
            }
          ]
        }
      }
      File.write(settings_path, JSON.pretty_generate(settings))

      result = command.send(:remove_hooks_from_file, settings_path)

      expect(result).to be true

      updated = JSON.parse(File.read(settings_path))
      expect(updated["hooks"]["Stop"].size).to eq(1)
      expect(updated["hooks"]["Stop"][0]["hooks"][0]["command"]).to eq("some-other-command")
    end

    it "removes hooks key if all hooks are claude-memory hooks" do
      settings = {
        "hooks" => {
          "Stop" => [{
            "hooks" => [
              {"type" => "command", "command" => "claude-memory hook ingest", "timeout" => 10}
            ]
          }]
        }
      }
      File.write(settings_path, JSON.pretty_generate(settings))

      command.send(:remove_hooks_from_file, settings_path)

      updated = JSON.parse(File.read(settings_path))
      expect(updated["hooks"]).to be_nil
    end
  end
end
