# frozen_string_literal: true

require "fileutils"

module ClaudeMemory
  module Commands
    module Initializers
      # Orchestrates project-local ClaudeMemory initialization
      class ProjectInitializer
        def initialize(stdout, stderr, stdin)
          @stdout = stdout
          @stderr = stderr
          @stdin = stdin
        end

        def initialize_memory
          @stdout.puts "Initializing ClaudeMemory (project-local)...\n\n"

          # Check for existing hooks and offer options
          hooks_config = HooksConfigurator.new(@stdout)
          if hooks_config.has_claude_memory_hooks?(".claude/settings.json")
            handle_existing_hooks(hooks_config)
            return 0 if @skip_initialization
          end

          ensure_databases
          ensure_directories
          configure_hooks unless @skip_hooks
          configure_mcp
          configure_memory_instructions
          install_output_style

          print_completion_message
          0
        end

        private

        def handle_existing_hooks(hooks_config)
          @stdout.puts "⚠️  Existing claude-memory hooks detected in .claude/settings.json"
          @stdout.puts "\nOptions:"
          @stdout.puts "  1. Update to current version (recommended)"
          @stdout.puts "  2. Remove hooks (uninstall)"
          @stdout.puts "  3. Leave as-is (skip)"
          @stdout.print "\nChoice [1]: "

          choice = @stdin.gets.to_s.strip
          choice = "1" if choice.empty?

          case choice
          when "2"
            @stdout.puts "\nRemoving hooks..."
            hooks_config.remove_hooks_from_file(".claude/settings.json")
            @stdout.puts "✓ Hooks removed. Run 'claude-memory uninstall' for full cleanup."
            @skip_initialization = true
          when "3"
            @stdout.puts "\nSkipping hook configuration."
            @skip_hooks = true
          else
            @stdout.puts "\nUpdating hooks..."
          end
        end

        def ensure_databases
          DatabaseEnsurer.new(@stdout).ensure_project_databases
        end

        def ensure_directories
          FileUtils.mkdir_p(".claude/rules")
          @stdout.puts "✓ Created .claude/rules directory"
        end

        def configure_hooks
          HooksConfigurator.new(@stdout).configure_project_hooks
        end

        def configure_mcp
          McpConfigurator.new(@stdout).configure_project_mcp
        end

        def configure_memory_instructions
          MemoryInstructionsWriter.new(@stdout).write_project_instructions
        end

        def install_output_style
          style_source = File.join(__dir__, "../../../output_styles/claude_memory.json")
          style_dest = ".claude/output_styles/claude_memory.json"

          return unless File.exist?(style_source)

          FileUtils.mkdir_p(File.dirname(style_dest))
          FileUtils.cp(style_source, style_dest)
          @stdout.puts "✓ Installed output style at #{style_dest}"
        end

        def print_completion_message
          @stdout.puts "\n=== Setup Complete ===\n"
          @stdout.puts "ClaudeMemory is now configured for this project."
          @stdout.puts "\nDatabases:"
          @stdout.puts "  Global: ~/.claude/memory.sqlite3 (user-wide knowledge)"
          @stdout.puts "  Project: .claude/memory.sqlite3 (project-specific)"
          @stdout.puts "\nNext steps:"
          @stdout.puts "  1. Restart Claude Code to load the new configuration"
          @stdout.puts "  2. Use Claude Code normally - transcripts will be ingested automatically"
          @stdout.puts "  3. Run 'claude-memory promote <fact_id>' to move facts to global"
          @stdout.puts "  4. Run 'claude-memory doctor' to verify setup"
        end
      end
    end
  end
end
