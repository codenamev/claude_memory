# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"

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
    it "returns CLAUDE_PROJECT_DIR when it is not inside a git repo" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/path/to/project"})
      allow(config).to receive(:git_command).and_return(nil)

      expect(config.project_dir).to eq("/path/to/project")
    end

    it "resolves git repo root for regular repos" do
      config = described_class.new({})
      allow(config).to receive(:git_command).with(Dir.pwd, "rev-parse", "--git-common-dir").and_return(".git")
      allow(config).to receive(:git_command).with(Dir.pwd, "rev-parse", "--show-toplevel").and_return("/repo/root")

      expect(config.project_dir).to eq("/repo/root")
    end

    it "resolves main repo root when inside a git worktree" do
      config = described_class.new({})
      allow(config).to receive(:git_command).with(Dir.pwd, "rev-parse", "--git-common-dir").and_return("/main/repo/.git")
      allow(File).to receive(:realpath).with("/main/repo/.git").and_return("/main/repo/.git")

      expect(config.project_dir).to eq("/main/repo")
    end

    # Claude Code sets CLAUDE_PROJECT_DIR on every hook and MCP subprocess, to
    # the directory the session started in. Returning it as-is skipped the
    # worktree resolution entirely and gave each worktree its own database.
    it "resolves CLAUDE_PROJECT_DIR through the git root when it names a worktree" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/wt/feature"})
      allow(config).to receive(:git_command).with("/wt/feature", "rev-parse", "--git-common-dir").and_return("/main/repo/.git")
      allow(File).to receive(:realpath).with("/main/repo/.git").and_return("/main/repo/.git")

      expect(config.project_dir).to eq("/main/repo")
    end

    it "resolves CLAUDE_PROJECT_DIR up to the repo root when it names a subdirectory" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/repo/root/backend"})
      allow(config).to receive(:git_command).with("/repo/root/backend", "rev-parse", "--git-common-dir").and_return(".git")
      allow(config).to receive(:git_command).with("/repo/root/backend", "rev-parse", "--show-toplevel").and_return("/repo/root")

      expect(config.project_dir).to eq("/repo/root")
    end

    it "uses Dir.pwd when CLAUDE_MEMORY_ISOLATE_WORKTREES is set" do
      config = described_class.new({"CLAUDE_MEMORY_ISOLATE_WORKTREES" => "1"})
      expect(config.project_dir).to eq(Dir.pwd)
    end

    it "keeps CLAUDE_PROJECT_DIR unresolved when CLAUDE_MEMORY_ISOLATE_WORKTREES is set" do
      config = described_class.new({
        "CLAUDE_PROJECT_DIR" => "/wt/feature",
        "CLAUDE_MEMORY_ISOLATE_WORKTREES" => "1"
      })
      expect(config).not_to receive(:git_command)

      expect(config.project_dir).to eq("/wt/feature")
    end

    context "against a real git worktree" do
      let(:tmp) { Dir.mktmpdir("cm-worktree") }
      let(:repo) { File.join(tmp, "repo") }
      let(:worktree) { File.join(tmp, "wt") }

      # git exports GIT_DIR, GIT_INDEX_FILE and friends to its own hooks, so a
      # suite run from pre-commit inherits them and every git call below acts
      # on the wrong repository. Scrub them, and raise on failure instead of
      # discarding stderr - a fixture that silently fails to build breaks a
      # later expectation, somewhere that does not name the cause.
      def git!(*args)
        out, status = Open3.capture2e(ClaudeMemory::Configuration::GIT_ENV_SCRUB, "git", *args)
        raise "git #{args.join(" ")} failed: #{out}" unless status.success?
        out
      end

      before do
        FileUtils.mkdir_p(repo)
        git!("init", "-q", repo)
        git!("-C", repo, "config", "user.email", "t@example.com")
        git!("-C", repo, "config", "user.name", "t")
        File.write(File.join(repo, "README"), "x")
        git!("-C", repo, "add", "README")
        git!("-C", repo, "commit", "-qm", "init")
        git!("-C", repo, "worktree", "add", "-q", worktree, "-b", "feature")
        raise "worktree fixture was not created" unless File.directory?(worktree)
      end

      after { FileUtils.remove_entry(tmp) }

      it "maps a worktree named by CLAUDE_PROJECT_DIR back to the main repo" do
        config = described_class.new({"CLAUDE_PROJECT_DIR" => worktree})
        expect(File.realpath(config.project_dir)).to eq(File.realpath(repo))
      end

      it "gives the worktree and the main repo the same project database" do
        from_worktree = described_class.new({"CLAUDE_PROJECT_DIR" => worktree}).project_db_path
        from_repo = described_class.new({"CLAUDE_PROJECT_DIR" => repo}).project_db_path

        expect(File.realpath(File.dirname(from_worktree, 2)))
          .to eq(File.realpath(File.dirname(from_repo, 2)))
      end

      it "still isolates the worktree when CLAUDE_MEMORY_ISOLATE_WORKTREES is set" do
        config = described_class.new({
          "CLAUDE_PROJECT_DIR" => worktree,
          "CLAUDE_MEMORY_ISOLATE_WORKTREES" => "1"
        })
        expect(config.project_dir).to eq(worktree)
      end
    end

    it "falls back to Dir.pwd when git is not available" do
      config = described_class.new({})
      allow(config).to receive(:git_command).and_return(nil)

      expect(config.project_dir).to eq(Dir.pwd)
    end

    it "falls back to Dir.pwd when not in a git repo" do
      config = described_class.new({})
      allow(config).to receive(:git_command).with(Dir.pwd, "rev-parse", "--git-common-dir").and_return(nil)

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
