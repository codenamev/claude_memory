# frozen_string_literal: true

require "open3"
require "json"

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

    # Default staleness threshold (in days) for #35 access-based staleness.
    # Active facts whose last_recalled_at is older than this — or never set,
    # for facts created earlier than the same window — are flagged as
    # candidates for review. Override via CLAUDE_MEMORY_STALE_DAYS.
    DEFAULT_STALE_DAYS = 14

    # @return [Integer] staleness threshold in days
    def stale_days
      raw = env["CLAUDE_MEMORY_STALE_DAYS"]
      return DEFAULT_STALE_DAYS if raw.nil? || raw.empty?
      parsed = Integer(raw, 10)
      (parsed > 0) ? parsed : DEFAULT_STALE_DAYS
    rescue ArgumentError
      DEFAULT_STALE_DAYS
    end

    # Threshold (in days) for the context-injection staleness marker. A
    # single-value fact older than this and not recalled within it gets a
    # "verify before relying" annotation when injected at SessionStart.
    # Deliberately much longer than DEFAULT_STALE_DAYS (the dashboard's
    # review-candidate window) — the injection marker should fire only on
    # facts old enough to be genuinely risky, not merely unused for a
    # couple weeks. Override via CLAUDE_MEMORY_INJECTION_STALE_DAYS.
    DEFAULT_INJECTION_STALE_DAYS = 180

    # @return [Integer] injection staleness threshold in days
    def injection_stale_days
      raw = env["CLAUDE_MEMORY_INJECTION_STALE_DAYS"]
      return DEFAULT_INJECTION_STALE_DAYS if raw.nil? || raw.empty?
      parsed = Integer(raw, 10)
      (parsed > 0) ? parsed : DEFAULT_INJECTION_STALE_DAYS
    rescue ArgumentError
      DEFAULT_INJECTION_STALE_DAYS
    end

    # Whether OTel trace ingestion is opted in. Reads OTEL_TRACES_EXPORTER
    # from .claude/settings.json's env block. Traces are off unless the
    # value is present and non-empty and not "none". Set by
    # `claude-memory otel --enable-traces`.
    #
    # @return [Boolean]
    def otel_traces_enabled?
      value = settings_env["OTEL_TRACES_EXPORTER"]
      return false if value.nil?
      stripped = value.to_s.strip
      !stripped.empty? && stripped != "none"
    end

    # Read the env block from .claude/settings.json (project scope) so
    # callers can inspect what Claude Code sees at session start. Returns
    # an empty hash when the file is missing or unparseable — matches the
    # tolerant behavior of Claude Code's settings loader.
    #
    # @return [Hash]
    def settings_env
      path = settings_json_path
      return {} unless path
      raw = File.read(path)
      parsed = JSON.parse(raw)
      env_block = parsed.is_a?(Hash) ? parsed["env"] : nil
      env_block.is_a?(Hash) ? env_block : {}
    rescue JSON::ParserError, Errno::ENOENT
      {}
    end

    # Path to the project-scoped settings.json. nil when no project_dir
    # exists (e.g. running outside any directory).
    #
    # @return [String, nil]
    def settings_json_path
      dir = project_dir
      return nil unless dir
      File.join(dir, ".claude", "settings.json")
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
