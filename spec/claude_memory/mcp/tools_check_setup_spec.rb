# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::MCP::Tools, "#check_setup" do
  let(:store) do
    # Create a minimal in-memory database for tools initialization
    # check_setup doesn't use the store, but Tools initializer needs it
    db_path = File.join(@tmpdir, "test.db") if @tmpdir
    ClaudeMemory::Store::SQLiteStore.new(db_path || ":memory:")
  end
  let(:tools) { described_class.new(store) }

  after do
    store&.close
  end

  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      Dir.chdir(tmpdir) do
        ENV["HOME"] = tmpdir
        example.run
        ENV.delete("HOME")
      end
    end
  end

  describe "when not initialized" do
    it "returns not_initialized status" do
      result = tools.call("memory.check_setup", {})

      expect(result[:status]).to eq("not_initialized")
      expect(result[:initialized]).to be false
    end

    it "reports missing global database as an issue" do
      result = tools.call("memory.check_setup", {})

      expect(result[:issues]).to include(match(/Global database not found/))
    end

    it "reports missing project database as a warning" do
      result = tools.call("memory.check_setup", {})

      expect(result[:warnings]).to include(match(/Project database not found/))
    end

    it "recommends running init" do
      result = tools.call("memory.check_setup", {})

      expect(result[:recommendations]).to include("Run: claude-memory init")
    end

    it "reports all components as missing" do
      result = tools.call("memory.check_setup", {})

      expect(result[:components][:global_database]).to be false
      expect(result[:components][:project_database]).to be false
      expect(result[:components][:claude_md]).to be false
      expect(result[:components][:hooks_configured]).to be false
    end

    it "reports version as unknown" do
      result = tools.call("memory.check_setup", {})

      expect(result[:version][:current]).to eq("unknown")
      expect(result[:version][:latest]).to eq(ClaudeMemory::VERSION)
      expect(result[:version][:status]).to eq("unknown")
    end
  end

  describe "when partially initialized (databases exist, no CLAUDE.md)" do
    before do
      # Create databases
      FileUtils.mkdir_p(File.join(@tmpdir, ".claude"))
      FileUtils.touch(File.join(@tmpdir, ".claude", "memory.sqlite3"))

      FileUtils.mkdir_p(".claude")
      FileUtils.touch(".claude/memory.sqlite3")
    end

    it "returns partially_initialized status" do
      result = tools.call("memory.check_setup", {})

      expect(result[:status]).to eq("partially_initialized")
      expect(result[:initialized]).to be false
    end

    it "reports databases exist" do
      result = tools.call("memory.check_setup", {})

      expect(result[:components][:global_database]).to be true
      expect(result[:components][:project_database]).to be true
    end

    it "warns about missing CLAUDE.md" do
      result = tools.call("memory.check_setup", {})

      expect(result[:warnings]).to include(match(/No .claude\/CLAUDE.md found/))
    end
  end

  describe "when fully initialized with current version" do
    before do
      # Create databases
      FileUtils.mkdir_p(File.join(@tmpdir, ".claude"))
      FileUtils.touch(File.join(@tmpdir, ".claude", "memory.sqlite3"))

      FileUtils.mkdir_p(".claude")
      FileUtils.touch(".claude/memory.sqlite3")

      # Create CLAUDE.md with current version
      claude_md = <<~MD
        <!-- ClaudeMemory v#{ClaudeMemory::VERSION} -->
        # ClaudeMemory

        Memory configuration...
      MD
      File.write(".claude/CLAUDE.md", claude_md)

      # Create hooks configuration
      settings = {
        "hooks" => {
          "SessionStart" => [{"hooks" => [{"type" => "command", "command" => "claude-memory hook ingest"}]}]
        }
      }
      File.write(".claude/settings.json", JSON.pretty_generate(settings))
    end

    it "returns healthy status" do
      result = tools.call("memory.check_setup", {})

      expect(result[:status]).to eq("healthy")
      expect(result[:initialized]).to be true
    end

    it "reports all components as configured" do
      result = tools.call("memory.check_setup", {})

      expect(result[:components][:global_database]).to be true
      expect(result[:components][:project_database]).to be true
      expect(result[:components][:claude_md]).to be true
      expect(result[:components][:hooks_configured]).to be true
    end

    it "reports version as up_to_date" do
      result = tools.call("memory.check_setup", {})

      expect(result[:version][:current]).to eq(ClaudeMemory::VERSION)
      expect(result[:version][:latest]).to eq(ClaudeMemory::VERSION)
      expect(result[:version][:status]).to eq("up_to_date")
    end

    it "has no issues or warnings" do
      result = tools.call("memory.check_setup", {})

      expect(result[:issues]).to be_empty
      expect(result[:warnings]).to be_empty
    end

    it "has no recommendations" do
      result = tools.call("memory.check_setup", {})

      expect(result[:recommendations]).to be_empty
    end
  end

  describe "when initialized with outdated version" do
    before do
      # Create databases
      FileUtils.mkdir_p(File.join(@tmpdir, ".claude"))
      FileUtils.touch(File.join(@tmpdir, ".claude", "memory.sqlite3"))

      FileUtils.mkdir_p(".claude")
      FileUtils.touch(".claude/memory.sqlite3")

      # Create CLAUDE.md with old version
      claude_md = <<~MD
        <!-- ClaudeMemory v0.1.0 -->
        # ClaudeMemory

        Old memory configuration...
      MD
      File.write(".claude/CLAUDE.md", claude_md)
    end

    it "returns needs_upgrade status" do
      result = tools.call("memory.check_setup", {})

      expect(result[:status]).to eq("needs_upgrade")
      expect(result[:initialized]).to be true
    end

    it "reports version as outdated" do
      result = tools.call("memory.check_setup", {})

      expect(result[:version][:current]).to eq("0.1.0")
      expect(result[:version][:latest]).to eq(ClaudeMemory::VERSION)
      expect(result[:version][:status]).to eq("outdated")
    end

    it "warns about outdated version" do
      result = tools.call("memory.check_setup", {})

      expect(result[:warnings]).to include(match(/Configuration version.*is older than ClaudeMemory/))
    end

    it "recommends upgrade" do
      result = tools.call("memory.check_setup", {})

      expect(result[:recommendations]).to include(match(/upgrade/i))
    end
  end

  describe "when CLAUDE.md exists without version marker" do
    before do
      FileUtils.mkdir_p(".claude")
      FileUtils.touch(".claude/memory.sqlite3")

      # CLAUDE.md with ClaudeMemory section but no version marker
      claude_md = <<~MD
        # ClaudeMemory

        Old configuration without version marker...
      MD
      File.write(".claude/CLAUDE.md", claude_md)
    end

    it "reports no_version_marker status" do
      result = tools.call("memory.check_setup", {})

      expect(result[:version][:status]).to eq("no_version_marker")
    end

    it "warns about missing version marker" do
      result = tools.call("memory.check_setup", {})

      expect(result[:warnings]).to include(match(/no version marker/))
    end
  end

  describe "when CLAUDE.md exists without ClaudeMemory section" do
    before do
      FileUtils.mkdir_p(".claude")
      # Create CLAUDE.md without ClaudeMemory section
      File.write(".claude/CLAUDE.md", "# My Project\n\nSome other content\n")
    end

    it "warns about missing ClaudeMemory configuration" do
      result = tools.call("memory.check_setup", {})

      expect(result[:warnings]).to include(match(/no ClaudeMemory configuration found/))
    end
  end

  describe "hooks configuration detection" do
    before do
      FileUtils.mkdir_p(".claude")
    end

    it "detects hooks in settings.json" do
      settings = {"hooks" => {"SessionStart" => []}}
      File.write(".claude/settings.json", JSON.pretty_generate(settings))

      result = tools.call("memory.check_setup", {})
      expect(result[:components][:hooks_configured]).to be true
    end

    it "detects hooks in settings.local.json" do
      settings = {"hooks" => {"Stop" => []}}
      File.write(".claude/settings.local.json", JSON.pretty_generate(settings))

      result = tools.call("memory.check_setup", {})
      expect(result[:components][:hooks_configured]).to be true
    end

    it "handles invalid JSON gracefully" do
      File.write(".claude/settings.json", "{invalid json")

      result = tools.call("memory.check_setup", {})
      expect(result[:components][:hooks_configured]).to be false
      expect(result[:warnings]).to include(match(/Invalid JSON/))
    end

    it "warns when no hooks configured" do
      result = tools.call("memory.check_setup", {})

      expect(result[:warnings]).to include(match(/No hooks configured/))
    end
  end
end
