# frozen_string_literal: true

require "open3"

module ClaudeMemory
  # Centralized configuration and ENV access
  # Provides consistent access to paths and environment variables
  class Configuration
    attr_reader :env

    # @param env [Hash] environment variables (default: ENV)
    def initialize(env = ENV)
      @env = env
    end

    # @return [String] user home directory
    def home_dir
      env["HOME"] || File.expand_path("~")
    end

    # @return [String] project root directory (resolves git worktrees)
    def project_dir
      env["CLAUDE_PROJECT_DIR"] || resolve_project_dir
    end

    # @return [String] Claude config directory (default: ~/.claude)
    def claude_config_dir
      env["CLAUDE_CONFIG_DIR"] || File.join(home_dir, ".claude")
    end

    # @return [String] path to global memory database
    def global_db_path
      File.join(claude_config_dir, "memory.sqlite3")
    end

    # @param project_path [String, nil] override project root (defaults to project_dir)
    # @return [String] path to project memory database
    def project_db_path(project_path = nil)
      path = project_path || project_dir
      File.join(path, ".claude", "memory.sqlite3")
    end

    # @return [String, nil] current Claude session ID from CLAUDE_SESSION_ID
    def session_id
      env["CLAUDE_SESSION_ID"]
    end

    # @return [String, nil] path to current transcript from CLAUDE_TRANSCRIPT_PATH
    def transcript_path
      env["CLAUDE_TRANSCRIPT_PATH"]
    end

    private

    def resolve_project_dir
      return Dir.pwd if env["CLAUDE_MEMORY_ISOLATE_WORKTREES"]

      git_main_repo_root || Dir.pwd
    end

    # Resolve main repository root, even when running inside a git worktree.
    # Uses --git-common-dir which returns the shared .git directory across
    # all worktrees, preventing duplicate project databases per worktree.
    def git_main_repo_root
      common_dir = git_command("rev-parse --git-common-dir")
      return nil unless common_dir

      if common_dir == ".git"
        git_command("rev-parse --show-toplevel")
      else
        # Worktree - common_dir is absolute path to main repo's .git dir
        # (or .git/worktrees parent). Resolve to repo root.
        File.dirname(File.realpath(common_dir))
      end
    rescue Errno::ENOENT
      # git not available or path doesn't exist
      nil
    end

    # Run a git command and return stripped output, or nil on failure
    def git_command(args)
      output, status = Open3.capture2("git #{args}", err: File::NULL)
      return nil unless status.success?
      stripped = output.strip
      stripped.empty? ? nil : stripped
    rescue Errno::ENOENT
      nil
    end
  end
end
