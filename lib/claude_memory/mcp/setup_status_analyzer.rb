# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Pure logic for analyzing setup status and generating recommendations
    # Follows Functional Core pattern - no I/O, just decision logic
    class SetupStatusAnalyzer
      # Determine overall setup status based on component states
      # @param global_db_exists [Boolean] Global database exists
      # @param claude_md_exists [Boolean] CLAUDE.md file exists
      # @param version_status [String, nil] Version status (up_to_date, outdated, etc.)
      # @return [String] Overall status (healthy, needs_upgrade, partially_initialized, not_initialized)
      def self.determine_status(global_db_exists, claude_md_exists, version_status)
        initialized = global_db_exists && claude_md_exists

        if initialized && version_status == "up_to_date"
          "healthy"
        elsif initialized && version_status == "outdated"
          "needs_upgrade"
        elsif global_db_exists && !claude_md_exists
          "partially_initialized"
        else
          "not_initialized"
        end
      end

      # Generate recommendations based on setup status
      # @param initialized [Boolean] Whether system is initialized
      # @param version_status [String, nil] Version status
      # @param has_warnings [Boolean] Whether there are warnings
      # @return [Array<String>] List of recommendations
      def self.generate_recommendations(initialized, version_status, has_warnings)
        recommendations = []

        if !initialized
          recommendations << "Run: claude-memory init"
          recommendations << "This will create databases, configure hooks, and set up CLAUDE.md"
        elsif version_status == "outdated"
          recommendations << "Run: claude-memory upgrade (when available)"
          recommendations << "Or manually run: claude-memory init to update CLAUDE.md"
        elsif has_warnings
          recommendations << "Run: claude-memory doctor --fix (when available)"
          recommendations << "Or check individual issues and fix manually"
        end

        recommendations
      end

      # Extract version from CLAUDE.md content
      # @param content [String] CLAUDE.md file content
      # @return [String, nil] Extracted version or nil
      def self.extract_version(content)
        if content =~ /<!-- ClaudeMemory v([\d.]+) -->/
          $1
        end
      end

      # Determine version status by comparing current and latest
      # @param current_version [String, nil] Version from config
      # @param latest_version [String] Latest version
      # @return [String] Version status (up_to_date, outdated, no_version_marker, unknown)
      def self.determine_version_status(current_version, latest_version)
        return "unknown" unless current_version

        if current_version == latest_version
          "up_to_date"
        else
          "outdated"
        end
      end
    end
  end
end
