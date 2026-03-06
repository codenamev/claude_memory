# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::Initializers::ProjectInitializer do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:stdin) { StringIO.new }
  let(:initializer) { described_class.new(stdout, stderr, stdin) }

  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      Dir.chdir(tmpdir) do
        ENV["HOME"] = tmpdir
        example.run
      end
    end
  end

  after do
    ENV.delete("HOME")
    ENV.delete("CLAUDE_PLUGIN_ROOT")
  end

  context "in plugin mode" do
    before do
      ENV["CLAUDE_PLUGIN_ROOT"] = "/fake/plugin/root"
    end

    it "returns exit code 0" do
      expect(initializer.initialize_memory).to eq(0)
    end

    it "creates project database" do
      initializer.initialize_memory
      expect(File.exist?(".claude/memory.sqlite3")).to be true
    end

    it "creates .claude/rules directory" do
      initializer.initialize_memory
      expect(File.directory?(".claude/rules")).to be true
    end

    it "creates memory instructions in .claude/CLAUDE.md" do
      initializer.initialize_memory
      expect(File.exist?(".claude/CLAUDE.md")).to be true
    end

    it "does not create .claude/settings.json (hooks)" do
      initializer.initialize_memory
      expect(File.exist?(".claude/settings.json")).to be false
    end

    it "does not create .claude.json (MCP)" do
      initializer.initialize_memory
      expect(File.exist?(".claude.json")).to be false
    end

    it "does not create output style" do
      initializer.initialize_memory
      expect(File.exist?(".claude/output_styles/claude_memory.json")).to be false
    end

    it "prints plugin mode message" do
      initializer.initialize_memory
      expect(stdout.string).to include("Plugin mode detected")
    end

    it "prints plugin-specific completion message" do
      initializer.initialize_memory
      expect(stdout.string).to include("managed by the plugin")
      expect(stdout.string).not_to include("Restart Claude Code")
    end
  end

  context "outside plugin mode" do
    it "creates hooks in .claude/settings.json" do
      initializer.initialize_memory
      expect(File.exist?(".claude/settings.json")).to be true
    end

    it "creates MCP config in .claude.json" do
      initializer.initialize_memory
      expect(File.exist?(".claude.json")).to be true
    end

    it "prints restart reminder" do
      initializer.initialize_memory
      expect(stdout.string).to include("Restart Claude Code")
    end
  end
end
