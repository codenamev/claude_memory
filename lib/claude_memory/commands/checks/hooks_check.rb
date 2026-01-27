# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Commands
    module Checks
      # Checks hooks configuration in settings files
      class HooksCheck
        SETTINGS_PATHS = [".claude/settings.json", ".claude/settings.local.json"].freeze
        EXPECTED_HOOKS = %w[Stop SessionStart PreCompact SessionEnd].freeze

        def call
          hooks_found = false
          warnings = []
          paths_checked = []

          SETTINGS_PATHS.each do |path|
            next unless File.exist?(path)

            paths_checked << path
            result = check_settings_file(path)

            if result[:has_hooks]
              hooks_found = true
              warnings.concat(result[:warnings])
            end
          end

          # Check for orphaned hooks
          if hooks_found && !mcp_configured?
            warnings << "Orphaned hooks detected: claude-memory hooks are configured but MCP server is not"
            warnings << "Run 'claude-memory uninstall' to remove hooks, or 'claude-memory init' to reconfigure"
          end

          if hooks_found
            {
              status: warnings.any? ? :warning : :ok,
              label: "hooks",
              message: "Hooks configured in #{paths_checked.join(", ")}",
              details: {
                paths: paths_checked,
                fallback_available: false
              },
              warnings: warnings
            }
          else
            {
              status: :warning,
              label: "hooks",
              message: "No hooks configured. Run 'claude-memory init' or configure manually.",
              details: {
                paths: SETTINGS_PATHS,
                fallback_available: true,
                fallback_commands: [
                  "claude-memory ingest --session-id <id> --transcript-path <path>",
                  "claude-memory sweep --budget 5",
                  "claude-memory publish"
                ]
              },
              warnings: []
            }
          end
        end

        private

        def check_settings_file(path)
          warnings = []

          begin
            config = JSON.parse(File.read(path))

            unless config["hooks"]&.any?
              return {has_hooks: false, warnings: []}
            end

            # Check if any hooks contain claude-memory commands
            claude_memory_hooks = config["hooks"].values.flatten.any? do |hook_array|
              next false unless hook_array.is_a?(Hash) && hook_array["hooks"].is_a?(Array)
              hook_array["hooks"].any? { |h| h["command"]&.include?("claude-memory") }
            end

            return {has_hooks: false, warnings: []} unless claude_memory_hooks

            # Check for missing recommended hooks
            missing = EXPECTED_HOOKS - config["hooks"].keys
            if missing.any?
              warnings << "Missing recommended hooks in #{path}: #{missing.join(", ")}"
            end

            {has_hooks: true, warnings: warnings}
          rescue JSON::ParserError
            {has_hooks: false, warnings: ["Invalid JSON in #{path}"]}
          end
        end

        def mcp_configured?
          mcp_path = ".claude.json"
          return false unless File.exist?(mcp_path)

          begin
            config = JSON.parse(File.read(mcp_path))
            config["mcpServers"]&.key?("claude-memory")
          rescue JSON::ParserError
            false
          end
        end
      end
    end
  end
end
