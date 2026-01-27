# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Initializers
      # Orchestrates global ClaudeMemory initialization
      class GlobalInitializer
        def initialize(stdout, stderr, stdin)
          @stdout = stdout
          @stderr = stderr
          @stdin = stdin
        end

        def initialize_memory
          @stdout.puts "Initializing ClaudeMemory (global only)...\n\n"

          # Check for existing hooks in global settings
          hooks_config = HooksConfigurator.new(@stdout)
          global_settings = File.join(Dir.home, ".claude", "settings.json")
          if hooks_config.has_claude_memory_hooks?(global_settings)
            handle_existing_hooks(hooks_config, global_settings)
            return 0 if @skip_initialization
          end

          ensure_database
          configure_hooks unless @skip_hooks
          configure_mcp
          configure_memory_instructions

          print_completion_message
          0
        end

        private

        def handle_existing_hooks(hooks_config, global_settings)
          @stdout.puts "⚠️  Existing claude-memory hooks detected in #{global_settings}"
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
            hooks_config.remove_hooks_from_file(global_settings)
            @stdout.puts "✓ Hooks removed. Run 'claude-memory uninstall --global' for full cleanup."
            @skip_initialization = true
          when "3"
            @stdout.puts "\nSkipping hook configuration."
            @skip_hooks = true
          else
            @stdout.puts "\nUpdating hooks..."
          end
        end

        def ensure_database
          DatabaseEnsurer.new(@stdout).ensure_global_database
        end

        def configure_hooks
          HooksConfigurator.new(@stdout).configure_global_hooks
        end

        def configure_mcp
          McpConfigurator.new(@stdout).configure_global_mcp
        end

        def configure_memory_instructions
          MemoryInstructionsWriter.new(@stdout).write_global_instructions
        end

        def print_completion_message
          @stdout.puts "\n=== Global Setup Complete ===\n"
          @stdout.puts "ClaudeMemory is now configured globally."
          @stdout.puts "\nNote: Run 'claude-memory init' in each project for project-specific memory."
        end
      end
    end
  end
end
