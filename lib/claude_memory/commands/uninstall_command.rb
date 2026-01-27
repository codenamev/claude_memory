# frozen_string_literal: true

require "fileutils"
require "json"

module ClaudeMemory
  module Commands
    # Removes ClaudeMemory configuration from a project or globally
    class UninstallCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {global: false, full: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory uninstall [options]"
            parser.on("--global", "Uninstall from global ~/.claude/ settings") { o[:global] = true }
            parser.on("--full", "Remove databases and all configuration (not just hooks)") { o[:full] = true }
          end
        end
        return 1 if opts.nil?

        if opts[:global]
          uninstall_global(opts[:full])
        else
          uninstall_local(opts[:full])
        end
      end

      private

      def uninstall_local(full)
        stdout.puts "Uninstalling ClaudeMemory (project-local)...\n\n"

        removed_items = []

        # Remove hooks from settings.json
        if remove_hooks_from_file(".claude/settings.json")
          removed_items << "Hooks from .claude/settings.json"
        end

        # Remove MCP server from .claude.json
        if remove_mcp_server(".claude.json")
          removed_items << "MCP server from .claude.json"
        end

        # Remove ClaudeMemory section from .claude/CLAUDE.md
        if remove_claude_md_section(".claude/CLAUDE.md")
          removed_items << "ClaudeMemory section from .claude/CLAUDE.md"
        end

        if full
          # Remove databases and generated files
          files_to_remove = [
            ".claude/memory.sqlite3",
            ".claude/rules/claude_memory.generated.md",
            ".claude/output_styles/claude_memory.json"
          ]

          files_to_remove.each do |file|
            if File.exist?(file)
              FileUtils.rm_f(file)
              removed_items << "Removed #{file}"
            end
          end
        end

        stdout.puts "\n=== Uninstall Complete ===\n"
        if removed_items.any?
          stdout.puts "Removed:"
          removed_items.each { |item| stdout.puts "  ✓ #{item}" }
        else
          stdout.puts "No ClaudeMemory configuration found."
        end

        if full
          stdout.puts "\nNote: Global database (~/.claude/memory.sqlite3) was NOT removed."
          stdout.puts "      Run 'claude-memory uninstall --global --full' to remove it."
        else
          stdout.puts "\nNote: Project database (.claude/memory.sqlite3) was NOT removed."
          stdout.puts "      Run with --full flag to remove all files."
        end

        stdout.puts "\nRestart Claude Code to complete uninstallation."

        0
      end

      def uninstall_global(full)
        stdout.puts "Uninstalling ClaudeMemory (global)...\n\n"

        removed_items = []

        # Remove hooks from ~/.claude/settings.json
        global_settings = File.join(Dir.home, ".claude", "settings.json")
        if remove_hooks_from_file(global_settings)
          removed_items << "Hooks from #{global_settings}"
        end

        # Remove MCP server from ~/.claude.json
        global_mcp = File.join(Dir.home, ".claude.json")
        if remove_mcp_server(global_mcp)
          removed_items << "MCP server from #{global_mcp}"
        end

        # Remove ClaudeMemory section from ~/.claude/CLAUDE.md
        global_claude_md = File.join(Dir.home, ".claude", "CLAUDE.md")
        if remove_claude_md_section(global_claude_md)
          removed_items << "ClaudeMemory section from #{global_claude_md}"
        end

        if full
          # Remove global database
          global_db = ClaudeMemory.global_db_path
          if File.exist?(global_db)
            FileUtils.rm_f(global_db)
            removed_items << "Removed #{global_db}"
          end
        end

        stdout.puts "\n=== Global Uninstall Complete ===\n"
        if removed_items.any?
          stdout.puts "Removed:"
          removed_items.each { |item| stdout.puts "  ✓ #{item}" }
        else
          stdout.puts "No ClaudeMemory configuration found."
        end

        if full
          stdout.puts "\nWarning: Global database was removed. All user-wide knowledge is deleted."
        else
          stdout.puts "\nNote: Global database (~/.claude/memory.sqlite3) was NOT removed."
          stdout.puts "      Run with --full flag to remove all files."
        end

        stdout.puts "\nRestart Claude Code to complete uninstallation."

        0
      end

      # Removes claude-memory hooks from a settings.json file
      # Returns true if hooks were removed, false otherwise
      def remove_hooks_from_file(settings_path)
        return false unless File.exist?(settings_path)

        begin
          config = JSON.parse(File.read(settings_path))
        rescue JSON::ParserError
          stderr.puts "Warning: Could not parse #{settings_path}, skipping hook removal"
          return false
        end

        return false unless config["hooks"]

        modified = false
        config["hooks"].each do |event, hook_arrays|
          next unless hook_arrays.is_a?(Array)

          # Filter out hook arrays that contain claude-memory commands
          original_count = hook_arrays.size
          hook_arrays.reject! do |hook_array|
            next false unless hook_array["hooks"].is_a?(Array)

            hook_array["hooks"].any? { |h| h["command"]&.include?("claude-memory") }
          end

          modified = true if hook_arrays.size < original_count

          # Remove empty event keys
          config["hooks"].delete(event) if hook_arrays.empty?
        end

        if modified
          # Remove hooks key entirely if empty
          config.delete("hooks") if config["hooks"].empty?

          File.write(settings_path, JSON.pretty_generate(config))
          true
        else
          false
        end
      end

      # Removes claude-memory MCP server from .claude.json
      # Returns true if server was removed, false otherwise
      def remove_mcp_server(mcp_path)
        return false unless File.exist?(mcp_path)

        begin
          config = JSON.parse(File.read(mcp_path))
        rescue JSON::ParserError
          stderr.puts "Warning: Could not parse #{mcp_path}, skipping MCP removal"
          return false
        end

        return false unless config["mcpServers"]&.key?("claude-memory")

        config["mcpServers"].delete("claude-memory")
        config.delete("mcpServers") if config["mcpServers"].empty?

        File.write(mcp_path, JSON.pretty_generate(config))
        true
      end

      # Removes ClaudeMemory section from CLAUDE.md
      # Returns true if section was removed, false otherwise
      def remove_claude_md_section(claude_md_path)
        return false unless File.exist?(claude_md_path)

        content = File.read(claude_md_path)
        return false unless content.include?("ClaudeMemory")

        # Remove ClaudeMemory section (marked by HTML comment through end of section)
        # Match from HTML comment through content until we hit another HTML comment or ## header
        modified_content = content.gsub(/<!-- ClaudeMemory v.*?-->.*?(?=^##|\n<!--|\Z)/m, "")

        # Clean up extra blank lines
        modified_content = modified_content.gsub(/\n{3,}/, "\n\n").strip

        if modified_content != content
          File.write(claude_md_path, modified_content)
          true
        else
          false
        end
      end
    end
  end
end
