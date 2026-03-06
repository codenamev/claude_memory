# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::Initializers::GlobalInitializer do
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

    it "creates global database" do
      initializer.initialize_memory
      global_db = File.join(@tmpdir, ".claude", "memory.sqlite3")
      expect(File.exist?(global_db)).to be true
    end

    it "creates global memory instructions" do
      initializer.initialize_memory
      claude_md = File.join(@tmpdir, ".claude", "CLAUDE.md")
      expect(File.exist?(claude_md)).to be true
    end

    it "does not create global hooks" do
      initializer.initialize_memory
      settings = File.join(@tmpdir, ".claude", "settings.json")
      expect(File.exist?(settings)).to be false
    end

    it "does not create global MCP config" do
      initializer.initialize_memory
      mcp_config = File.join(@tmpdir, ".claude.json")
      expect(File.exist?(mcp_config)).to be false
    end

    it "prints plugin mode message" do
      initializer.initialize_memory
      expect(stdout.string).to include("Plugin mode detected")
    end

    it "prints plugin-specific completion message" do
      initializer.initialize_memory
      expect(stdout.string).to include("managed by the plugin")
    end
  end

  context "outside plugin mode" do
    it "creates global hooks" do
      initializer.initialize_memory
      settings = File.join(@tmpdir, ".claude", "settings.json")
      expect(File.exist?(settings)).to be true
    end

    it "creates global MCP config" do
      initializer.initialize_memory
      mcp_config = File.join(@tmpdir, ".claude.json")
      expect(File.exist?(mcp_config)).to be true
    end
  end
end
