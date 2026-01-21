# frozen_string_literal: true

module ClaudeMemory
  # Centralized configuration and ENV access
  # Provides consistent access to paths and environment variables
  class Configuration
    attr_reader :env

    def initialize(env = ENV)
      @env = env
    end

    def home_dir
      env["HOME"] || File.expand_path("~")
    end

    def project_dir
      env["CLAUDE_PROJECT_DIR"] || Dir.pwd
    end

    def global_db_path
      File.join(home_dir, ".claude", "memory.sqlite3")
    end

    def project_db_path(project_path = nil)
      path = project_path || project_dir
      File.join(path, ".claude", "memory.sqlite3")
    end

    def session_id
      env["CLAUDE_SESSION_ID"]
    end

    def transcript_path
      env["CLAUDE_TRANSCRIPT_PATH"]
    end
  end
end
