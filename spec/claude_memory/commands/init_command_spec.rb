# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::InitCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      Dir.chdir(tmpdir) do
        example.run
      end
    end
  end

  describe "#call with project init" do
    before do
      # Mock home directory to avoid touching real ~/.claude
      ENV["HOME"] = @tmpdir
    end

    after do
      ENV.delete("HOME")
    end

    it "creates project database" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(File.exist?(".claude/memory.sqlite3")).to be true
    end

    it "creates global database" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      global_db = File.join(@tmpdir, ".claude", "memory.sqlite3")
      expect(File.exist?(global_db)).to be true
    end

    it "creates .claude/rules directory" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(File.directory?(".claude/rules")).to be true
    end

    it "configures hooks in .claude/settings.json" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(File.exist?(".claude/settings.json")).to be true

      config = JSON.parse(File.read(".claude/settings.json"))
      expect(config["hooks"]).to be_a(Hash)
      expect(config["hooks"]["SessionStart"]).not_to be_nil
      expect(config["hooks"]["Stop"]).not_to be_nil
    end

    it "configures MCP server in .claude.json" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(File.exist?(".claude.json")).to be true

      config = JSON.parse(File.read(".claude.json"))
      expect(config["mcpServers"]["claude-memory"]).to be_a(Hash)
      expect(config["mcpServers"]["claude-memory"]["command"]).to eq("claude-memory")
    end

    it "creates .claude/CLAUDE.md with version marker" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(File.exist?(".claude/CLAUDE.md")).to be true

      content = File.read(".claude/CLAUDE.md")
      expect(content).to include("<!-- ClaudeMemory v#{ClaudeMemory::VERSION} -->")
    end

    it "creates .claude/CLAUDE.md with memory-first workflow" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)

      content = File.read(".claude/CLAUDE.md")
      expect(content).to include("Memory-First Workflow")
      expect(content).to include("Check memory BEFORE reading files")
      expect(content).to include("memory.recall")
      expect(content).to include("memory.decisions")
    end

    it "prints success message" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Setup Complete")
      expect(stdout.string).to include("Restart Claude Code")
    end

    it "returns exit code 0 on success" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
    end

    context "when .claude/CLAUDE.md already exists" do
      it "appends memory instructions without duplicating" do
        FileUtils.mkdir_p(".claude")
        File.write(".claude/CLAUDE.md", "# My Project\n\nExisting content\n")

        command.call([])

        content = File.read(".claude/CLAUDE.md")
        expect(content).to include("# My Project")
        expect(content).to include("Existing content")
        expect(content).to include("ClaudeMemory")
        expect(content).to include("<!-- ClaudeMemory v#{ClaudeMemory::VERSION} -->")

        # Check version marker appears once
        expect(content.scan("<!-- ClaudeMemory v").size).to eq(1)
      end

      it "does not append if ClaudeMemory section already exists" do
        FileUtils.mkdir_p(".claude")
        existing_content = "# My Project\n\n<!-- ClaudeMemory v0.1.0 -->\n# ClaudeMemory\n\nExisting memory setup\n"
        File.write(".claude/CLAUDE.md", existing_content)

        command.call([])

        content = File.read(".claude/CLAUDE.md")
        # Should not duplicate ClaudeMemory sections
        expect(content.scan("# ClaudeMemory").size).to eq(1)
      end
    end
  end

  describe "#call with --global flag" do
    before do
      ENV["HOME"] = @tmpdir
    end

    after do
      ENV.delete("HOME")
    end

    it "creates only global database" do
      exit_code = command.call(["--global"])
      expect(exit_code).to eq(0)

      global_db = File.join(@tmpdir, ".claude", "memory.sqlite3")
      expect(File.exist?(global_db)).to be true
    end

    it "creates global CLAUDE.md with version marker" do
      exit_code = command.call(["--global"])
      expect(exit_code).to eq(0)

      claude_md = File.join(@tmpdir, ".claude", "CLAUDE.md")
      expect(File.exist?(claude_md)).to be true

      content = File.read(claude_md)
      expect(content).to include("<!-- ClaudeMemory v#{ClaudeMemory::VERSION} -->")
      expect(content).to include("ClaudeMemory provides long-term memory across all your sessions")
      expect(content).to include("Memory-First Workflow")
    end

    it "configures global hooks" do
      exit_code = command.call(["--global"])
      expect(exit_code).to eq(0)

      settings = File.join(@tmpdir, ".claude", "settings.json")
      expect(File.exist?(settings)).to be true

      config = JSON.parse(File.read(settings))
      expect(config["hooks"]).to be_a(Hash)
    end

    it "configures global MCP server" do
      exit_code = command.call(["--global"])
      expect(exit_code).to eq(0)

      mcp_config = File.join(@tmpdir, ".claude.json")
      expect(File.exist?(mcp_config)).to be true

      config = JSON.parse(File.read(mcp_config))
      expect(config["mcpServers"]["claude-memory"]).not_to be_nil
      expect(config["mcpServers"]["claude-memory"]["command"]).to eq("claude-memory")
    end

    it "prints global setup complete message" do
      exit_code = command.call(["--global"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Global Setup Complete")
      expect(stdout.string).to include("Run 'claude-memory init' in each project")
    end

    it "returns exit code 0" do
      exit_code = command.call(["--global"])
      expect(exit_code).to eq(0)
    end
  end

  describe "version marker format" do
    before do
      ENV["HOME"] = @tmpdir
    end

    after do
      ENV.delete("HOME")
    end

    it "uses semantic version format" do
      command.call([])
      content = File.read(".claude/CLAUDE.md")

      # Check version matches semantic versioning pattern
      expect(content).to match(/<!-- ClaudeMemory v\d+\.\d+\.\d+ -->/)
    end

    it "is an HTML comment that won't render in markdown" do
      command.call([])
      content = File.read(".claude/CLAUDE.md")

      # Starts with HTML comment syntax
      expect(content).to start_with("<!--")
      # First line ends with comment close
      expect(content.lines.first).to include("-->")
    end
  end

  describe "idempotency" do
    before do
      ENV["HOME"] = @tmpdir
    end

    after do
      ENV.delete("HOME")
    end

    it "can be run multiple times without duplicating hooks" do
      # First run
      command.call([])
      first_config = JSON.parse(File.read(".claude/settings.json"))
      first_hook_count = first_config["hooks"]["SessionStart"].size

      # Second run
      command.call([])
      second_config = JSON.parse(File.read(".claude/settings.json"))
      second_hook_count = second_config["hooks"]["SessionStart"].size

      # Should have same number of hooks
      expect(second_hook_count).to eq(first_hook_count)
    end

    it "preserves custom hooks when run multiple times" do
      # First run
      command.call([])

      # Add custom hook
      config = JSON.parse(File.read(".claude/settings.json"))
      custom_hook = {
        "hooks" => [
          {"type" => "command", "command" => "echo 'custom'", "timeout" => 5}
        ]
      }
      config["hooks"]["SessionStart"] << custom_hook
      File.write(".claude/settings.json", JSON.pretty_generate(config))

      # Second run
      command.call([])

      # Custom hook should still be present
      final_config = JSON.parse(File.read(".claude/settings.json"))
      custom_commands = final_config["hooks"]["SessionStart"].flat_map do |hook_array|
        hook_array["hooks"].map { |h| h["command"] }
      end

      expect(custom_commands).to include("echo 'custom'")
    end

    it "does not duplicate CLAUDE.md content" do
      # First run
      command.call([])
      first_content = File.read(".claude/CLAUDE.md")

      # Second run
      command.call([])
      second_content = File.read(".claude/CLAUDE.md")

      # Content should be identical
      expect(second_content).to eq(first_content)
    end

    it "handles existing databases gracefully" do
      # First run
      command.call([])
      expect(File.exist?(".claude/memory.sqlite3")).to be true

      # Second run should not fail
      expect { command.call([]) }.not_to raise_error
    end

    it "updates MCP server configuration on subsequent runs" do
      # First run
      command.call([])

      # Manually change MCP config
      config = JSON.parse(File.read(".claude.json"))
      config["mcpServers"]["claude-memory"]["args"] = ["old-args"]
      File.write(".claude.json", JSON.pretty_generate(config))

      # Second run should fix it
      command.call([])

      final_config = JSON.parse(File.read(".claude.json"))
      expect(final_config["mcpServers"]["claude-memory"]["args"]).to eq(["serve-mcp"])
    end
  end
end
