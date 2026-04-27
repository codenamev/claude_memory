# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Configuration do
  describe "#initialize" do
    it "accepts an ENV hash" do
      env = {"HOME" => "/home/user"}
      config = described_class.new(env)
      expect(config.env).to eq(env)
    end

    it "defaults to ENV" do
      config = described_class.new
      expect(config.env).to eq(ENV)
    end
  end

  describe "#home_dir" do
    it "returns HOME from env" do
      config = described_class.new({"HOME" => "/custom/home"})
      expect(config.home_dir).to eq("/custom/home")
    end

    it "falls back to File.expand_path when HOME missing" do
      config = described_class.new({})
      expect(config.home_dir).to eq(File.expand_path("~"))
    end
  end

  describe "#project_dir" do
    it "returns CLAUDE_PROJECT_DIR when set" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/path/to/project"})
      expect(config.project_dir).to eq("/path/to/project")
    end

    it "resolves git repo root for regular repos" do
      config = described_class.new({})
      allow(config).to receive(:git_command).with("rev-parse --git-common-dir").and_return(".git")
      allow(config).to receive(:git_command).with("rev-parse --show-toplevel").and_return("/repo/root")

      expect(config.project_dir).to eq("/repo/root")
    end

    it "resolves main repo root when inside a git worktree" do
      config = described_class.new({})
      allow(config).to receive(:git_command).with("rev-parse --git-common-dir").and_return("/main/repo/.git")
      allow(File).to receive(:realpath).with("/main/repo/.git").and_return("/main/repo/.git")

      expect(config.project_dir).to eq("/main/repo")
    end

    it "uses Dir.pwd when CLAUDE_MEMORY_ISOLATE_WORKTREES is set" do
      config = described_class.new({"CLAUDE_MEMORY_ISOLATE_WORKTREES" => "1"})
      expect(config.project_dir).to eq(Dir.pwd)
    end

    it "falls back to Dir.pwd when git is not available" do
      config = described_class.new({})
      allow(config).to receive(:git_command).and_return(nil)

      expect(config.project_dir).to eq(Dir.pwd)
    end

    it "falls back to Dir.pwd when not in a git repo" do
      config = described_class.new({})
      allow(config).to receive(:git_command).with("rev-parse --git-common-dir").and_return(nil)

      expect(config.project_dir).to eq(Dir.pwd)
    end
  end

  describe "#claude_config_dir" do
    it "returns CLAUDE_CONFIG_DIR when set" do
      config = described_class.new({"CLAUDE_CONFIG_DIR" => "/custom/claude"})
      expect(config.claude_config_dir).to eq("/custom/claude")
    end

    it "falls back to ~/.claude when CLAUDE_CONFIG_DIR not set" do
      config = described_class.new({"HOME" => "/home/user"})
      expect(config.claude_config_dir).to eq("/home/user/.claude")
    end
  end

  describe "#global_db_path" do
    it "returns path to global database" do
      config = described_class.new({"HOME" => "/home/user"})
      expect(config.global_db_path).to eq("/home/user/.claude/memory.sqlite3")
    end

    it "honors CLAUDE_CONFIG_DIR when set" do
      config = described_class.new({"CLAUDE_CONFIG_DIR" => "/alt/claude", "HOME" => "/home/user"})
      expect(config.global_db_path).to eq("/alt/claude/memory.sqlite3")
    end
  end

  describe "#project_db_path" do
    it "returns path to project database using project_dir" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/my/project"})
      expect(config.project_db_path).to eq("/my/project/.claude/memory.sqlite3")
    end

    it "uses Dir.pwd when CLAUDE_PROJECT_DIR not set" do
      config = described_class.new({})
      expected_path = File.join(Dir.pwd, ".claude/memory.sqlite3")
      expect(config.project_db_path).to eq(expected_path)
    end

    it "accepts explicit project_path override" do
      config = described_class.new({})
      path = config.project_db_path("/custom/path")
      expect(path).to eq("/custom/path/.claude/memory.sqlite3")
    end
  end

  describe "#session_id" do
    it "returns CLAUDE_SESSION_ID when set" do
      config = described_class.new({"CLAUDE_SESSION_ID" => "session-123"})
      expect(config.session_id).to eq("session-123")
    end

    it "returns nil when not set" do
      config = described_class.new({})
      expect(config.session_id).to be_nil
    end
  end

  describe "#transcript_path" do
    it "returns CLAUDE_TRANSCRIPT_PATH when set" do
      config = described_class.new({"CLAUDE_TRANSCRIPT_PATH" => "/tmp/transcript.jsonl"})
      expect(config.transcript_path).to eq("/tmp/transcript.jsonl")
    end

    it "returns nil when not set" do
      config = described_class.new({})
      expect(config.transcript_path).to be_nil
    end
  end

  describe "#stale_days" do
    it "defaults to 14 when env is empty" do
      expect(described_class.new({}).stale_days).to eq(14)
    end

    it "reads CLAUDE_MEMORY_STALE_DAYS when valid" do
      expect(described_class.new("CLAUDE_MEMORY_STALE_DAYS" => "30").stale_days).to eq(30)
    end

    it "falls back to default on non-numeric input" do
      expect(described_class.new("CLAUDE_MEMORY_STALE_DAYS" => "abc").stale_days).to eq(14)
    end

    it "falls back to default when set to zero or negative" do
      expect(described_class.new("CLAUDE_MEMORY_STALE_DAYS" => "0").stale_days).to eq(14)
      expect(described_class.new("CLAUDE_MEMORY_STALE_DAYS" => "-5").stale_days).to eq(14)
    end
  end
end
