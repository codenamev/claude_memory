# frozen_string_literal: true

require "json"

RSpec.describe "Plugin distribution files" do
  let(:project_root) { File.expand_path("../../..", __dir__) }

  describe ".claude-plugin/plugin.json" do
    let(:path) { File.join(project_root, ".claude-plugin", "plugin.json") }
    let(:plugin) { JSON.parse(File.read(path)) }

    it "exists" do
      expect(File.exist?(path)).to be true
    end

    it "is valid JSON" do
      expect { JSON.parse(File.read(path)) }.not_to raise_error
    end

    it "has required fields" do
      expect(plugin["name"]).to eq("claude-memory")
      expect(plugin["version"]).to be_a(String)
      expect(plugin["description"]).to be_a(String)
      expect(plugin["license"]).to eq("MIT")
    end

    it "has author information" do
      expect(plugin["author"]["name"]).to eq("Valentino Stoll")
    end

    it "has MCP server configuration" do
      expect(plugin["mcpServers"]).to be_a(Hash)
      expect(plugin["mcpServers"]["memory"]).to be_a(Hash)
      expect(plugin["mcpServers"]["memory"]["command"]).to include("serve-mcp.sh")
    end

    it "does not explicitly reference hooks (auto-loaded by Claude Code)" do
      expect(plugin).not_to have_key("hooks")
    end

    it "references commands directory" do
      expect(plugin["commands"]).to eq("./commands/")
    end

    # 0.12.1: plugin.json previously also declared "skills" and "outputStyles"
    # keys pointing at directories that didn't exist. Removed to avoid plugin
    # loader warnings — distill-transcripts.md is a flat command, not a skill
    # (per Claude Code's plugin reference). Reintroduce these assertions only
    # if/when those directories are populated.
    it "does not declare skills or output-styles directories that don't exist" do
      expect(plugin).not_to have_key("skills")
      expect(plugin).not_to have_key("outputStyles")
    end

    it "has version matching gem version" do
      expect(plugin["version"]).to eq(ClaudeMemory::VERSION)
    end
  end

  describe ".claude-plugin/marketplace.json" do
    let(:path) { File.join(project_root, ".claude-plugin", "marketplace.json") }
    let(:marketplace) { JSON.parse(File.read(path)) }

    it "exists" do
      expect(File.exist?(path)).to be true
    end

    it "is valid JSON" do
      expect { JSON.parse(File.read(path)) }.not_to raise_error
    end

    it "has plugin entry with version" do
      plugin_entry = marketplace["plugins"].first
      expect(plugin_entry["name"]).to eq("claude-memory")
      expect(plugin_entry["version"]).to eq(ClaudeMemory::VERSION)
    end

    it "has repository URL" do
      plugin_entry = marketplace["plugins"].first
      expect(plugin_entry["repository"]).to include("github.com")
    end
  end

  describe "hooks/hooks.json" do
    let(:path) { File.join(project_root, "hooks", "hooks.json") }
    let(:hooks) { JSON.parse(File.read(path)) }

    it "exists" do
      expect(File.exist?(path)).to be true
    end

    it "is valid JSON" do
      expect { JSON.parse(File.read(path)) }.not_to raise_error
    end

    it "has Stop hook" do
      expect(hooks["hooks"]["Stop"]).to be_a(Array)
    end

    it "has SessionStart hook" do
      expect(hooks["hooks"]["SessionStart"]).to be_a(Array)
    end

    it "has PreCompact hook" do
      expect(hooks["hooks"]["PreCompact"]).to be_a(Array)
    end

    it "has SessionEnd hook" do
      expect(hooks["hooks"]["SessionEnd"]).to be_a(Array)
    end

    it "uses hook-runner.sh wrapper" do
      all_commands = hooks["hooks"].values.flatten.flat_map { |group|
        group["hooks"].map { |h| h["command"] }
      }

      all_commands.each do |cmd|
        expect(cmd).to include("hook-runner.sh")
      end
    end
  end

  describe "referenced paths exist" do
    let(:plugin) { JSON.parse(File.read(File.join(project_root, ".claude-plugin", "plugin.json"))) }

    it "hooks file exists at standard location" do
      hooks_path = File.join(project_root, "hooks", "hooks.json")
      expect(File.exist?(hooks_path)).to be true
    end

    it "commands directory exists" do
      commands_path = File.join(project_root, plugin["commands"])
      expect(File.directory?(commands_path)).to be true
    end

    # 0.12.1: every directory key declared in plugin.json must exist on disk.
    # Previously plugin.json carried dead "skills" and "outputStyles" keys
    # pointing at missing directories; that's a plugin-loader warning source
    # and the documented cause of the user-facing "/distill-transcripts not
    # found" confusion in #upgrade-experience-2026-06-04.
    it "every directory key in plugin.json points at an existing directory" do
      %w[skills commands outputStyles].each do |key|
        next unless plugin.key?(key)
        path = File.join(project_root, plugin[key])
        expect(File.directory?(path)).to be(true), "plugin.json #{key.inspect} → #{plugin[key]} (missing on disk)"
      end
    end

    it "serve-mcp.sh script exists and is executable" do
      script = File.join(project_root, "scripts", "serve-mcp.sh")
      expect(File.exist?(script)).to be true
      expect(File.executable?(script)).to be true
    end

    it "hook-runner.sh script exists and is executable" do
      script = File.join(project_root, "scripts", "hook-runner.sh")
      expect(File.exist?(script)).to be true
      expect(File.executable?(script)).to be true
    end
  end
end
