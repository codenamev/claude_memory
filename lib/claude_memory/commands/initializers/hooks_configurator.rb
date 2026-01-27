# frozen_string_literal: true

require "fileutils"
require "json"

module ClaudeMemory
  module Commands
    module Initializers
      # Configures Claude Code hooks for ClaudeMemory
      class HooksConfigurator
        def initialize(stdout)
          @stdout = stdout
        end

        def configure_project_hooks
          settings_path = ".claude/settings.json"
          FileUtils.mkdir_p(File.dirname(settings_path))

          db_path = ClaudeMemory.project_db_path
          ingest_cmd = "claude-memory hook ingest --db #{db_path}"
          sweep_cmd = "claude-memory hook sweep --db #{db_path}"

          hooks_config = build_hooks_config(ingest_cmd, sweep_cmd)

          existing = load_json_file(settings_path)
          existing["hooks"] ||= {}
          merge_hooks!(existing["hooks"], hooks_config["hooks"])

          File.write(settings_path, JSON.pretty_generate(existing))
          @stdout.puts "✓ Configured hooks in #{settings_path}"
        end

        def configure_global_hooks
          settings_path = File.join(Dir.home, ".claude", "settings.json")
          FileUtils.mkdir_p(File.dirname(settings_path))

          db_path = ClaudeMemory.global_db_path
          ingest_cmd = "claude-memory hook ingest --db #{db_path}"
          sweep_cmd = "claude-memory hook sweep --db #{db_path}"

          hooks_config = build_hooks_config(ingest_cmd, sweep_cmd)

          existing = load_json_file(settings_path)
          existing["hooks"] ||= {}
          merge_hooks!(existing["hooks"], hooks_config["hooks"])

          File.write(settings_path, JSON.pretty_generate(existing))
          @stdout.puts "✓ Configured hooks in #{settings_path}"
        end

        def has_claude_memory_hooks?(settings_path)
          return false unless File.exist?(settings_path)

          begin
            config = JSON.parse(File.read(settings_path))
            return false unless config["hooks"]

            config["hooks"].values.flatten.any? do |hook_array|
              next false unless hook_array.is_a?(Hash) && hook_array["hooks"].is_a?(Array)
              hook_array["hooks"].any? { |h| h["command"]&.include?("claude-memory") }
            end
          rescue JSON::ParserError
            false
          end
        end

        def remove_hooks_from_file(settings_path)
          return unless File.exist?(settings_path)

          begin
            config = JSON.parse(File.read(settings_path))
          rescue JSON::ParserError
            return
          end

          return unless config["hooks"]

          config["hooks"].each do |event, hook_arrays|
            next unless hook_arrays.is_a?(Array)

            # Filter out hook arrays that contain claude-memory commands
            hook_arrays.reject! do |hook_array|
              next false unless hook_array["hooks"].is_a?(Array)
              hook_array["hooks"].any? { |h| h["command"]&.include?("claude-memory") }
            end

            # Remove empty event keys
            config["hooks"].delete(event) if hook_arrays.empty?
          end

          # Remove hooks key entirely if empty
          config.delete("hooks") if config["hooks"].empty?

          File.write(settings_path, JSON.pretty_generate(config))
        end

        private

        def build_hooks_config(ingest_cmd, sweep_cmd)
          {
            "hooks" => {
              "Stop" => [{
                "hooks" => [
                  {"type" => "command", "command" => ingest_cmd, "timeout" => 10}
                ]
              }],
              "SessionStart" => [{
                "hooks" => [
                  {"type" => "command", "command" => ingest_cmd, "timeout" => 10}
                ]
              }],
              "PreCompact" => [{
                "hooks" => [
                  {"type" => "command", "command" => ingest_cmd, "timeout" => 30},
                  {"type" => "command", "command" => sweep_cmd, "timeout" => 30}
                ]
              }],
              "SessionEnd" => [{
                "hooks" => [
                  {"type" => "command", "command" => ingest_cmd, "timeout" => 30},
                  {"type" => "command", "command" => sweep_cmd, "timeout" => 30}
                ]
              }]
            }
          }
        end

        def load_json_file(path)
          return {} unless File.exist?(path)
          JSON.parse(File.read(path))
        rescue JSON::ParserError
          {}
        end

        def merge_hooks!(existing_hooks, new_hooks)
          new_hooks.each do |event, hook_arrays|
            existing_hooks[event] ||= []

            hook_arrays.each do |hook_array|
              commands = hook_array["hooks"].map { |h| h["command"] }

              existing_commands = existing_hooks[event].flat_map do |existing_array|
                existing_array["hooks"]&.map { |h| h["command"] } || []
              end

              # Add hook array if none of its commands are already present
              unless commands.any? { |cmd| existing_commands.any? { |existing| existing&.include?("claude-memory") && existing.include?(cmd.split.last) } }
                existing_hooks[event] << hook_array
              end
            end
          end
        end
      end
    end
  end
end
