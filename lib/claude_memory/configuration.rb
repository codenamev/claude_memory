# frozen_string_literal: true

require "open3"
require "json"

module ClaudeMemory
  # Centralized configuration and ENV access
  # Provides consistent access to paths and environment variables
  class Configuration
    attr_reader :env

    # Environment overrides that clear git's per-invocation variables. A Hash
    # passed to Process.spawn is merged into the caller's environment, so a
    # filtered copy of ENV does not remove anything - only an explicit nil
    # unsets a variable.
    GIT_ENV_SCRUB = %w[
      GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
      GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
      GIT_PREFIX GIT_CEILING_DIRECTORIES
    ].to_h { |k| [k, nil] }.freeze

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
      base = env["CLAUDE_PROJECT_DIR"] || Dir.pwd
      return base if env["CLAUDE_MEMORY_ISOLATE_WORKTREES"]

      git_main_repo_root(base) || base
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

    # Resolve the main repository root for +dir+, even when +dir+ is a git
    # worktree. --git-common-dir returns the shared .git directory across all
    # worktrees, so every worktree of a repo maps to one project database.
    #
    # CLAUDE_PROJECT_DIR is resolved through here rather than returned as-is.
    # Claude Code sets it on every hook and MCP subprocess, pointing at the
    # directory the session started in, so reading it directly would skip this
    # entirely and mint a database per worktree. Asking for that is what
    # CLAUDE_MEMORY_ISOLATE_WORKTREES is for, and it still does exactly that.
    def git_main_repo_root(dir)
      common_dir = git_command(dir, "rev-parse", "--git-common-dir")
      return nil unless common_dir

      if common_dir == ".git"
        git_command(dir, "rev-parse", "--show-toplevel")
      else
        # Worktree - common_dir points at the main repo's .git dir. It can be
        # relative, and git resolves it against +dir+, not the process cwd.
        File.dirname(File.realpath(File.absolute_path(common_dir, dir)))
      end
    rescue Errno::ENOENT, Errno::ENOTDIR
      # git not available, or the path does not exist
      nil
    end

    # Run a git command in +dir+ and return stripped output, or nil on failure.
    # Array form, so a directory containing spaces or shell metacharacters is
    # passed through as one argument rather than reparsed by a shell.
    #
    # GIT_ENV_SCRUB is passed so -C decides the repository. git exports GIT_DIR
    # and GIT_INDEX_FILE to its own hooks, and those outrank -C, so a
    # claude-memory command invoked from a git hook would otherwise resolve
    # every project to whatever repository ran the hook.
    def git_command(dir, *args)
      output, status = Open3.capture2(GIT_ENV_SCRUB, "git", "-C", dir.to_s, *args, err: File::NULL)
      return nil unless status.success?
      stripped = output.strip
      stripped.empty? ? nil : stripped
    rescue Errno::ENOENT, Errno::ENOTDIR
      nil
    end
  end
end
