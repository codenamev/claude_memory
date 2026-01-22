# frozen_string_literal: true

require "fileutils"
require "json"

module ClaudeMemory
  module Commands
    # Initializes ClaudeMemory in a project or globally
    class InitCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {global: false}) do |o|
          OptionParser.new do |parser|
            parser.on("--global", "Install to global ~/.claude/ settings") { o[:global] = true }
          end
        end
        return 1 if opts.nil?

        if opts[:global]
          init_global
        else
          init_local
        end
      end

      private

      def init_local
        stdout.puts "Initializing ClaudeMemory (project-local)...\n\n"

        manager = ClaudeMemory::Store::StoreManager.new
        manager.ensure_global!
        stdout.puts "✓ Global database: #{manager.global_db_path}"
        manager.ensure_project!
        stdout.puts "✓ Project database: #{manager.project_db_path}"
        manager.close

        FileUtils.mkdir_p(".claude/rules")
        stdout.puts "✓ Created .claude/rules directory"

        configure_project_hooks
        configure_project_mcp
        install_output_style

        stdout.puts "\n=== Setup Complete ===\n"
        stdout.puts "ClaudeMemory is now configured for this project."
        stdout.puts "\nDatabases:"
        stdout.puts "  Global: ~/.claude/memory.sqlite3 (user-wide knowledge)"
        stdout.puts "  Project: .claude/memory.sqlite3 (project-specific)"
        stdout.puts "\nNext steps:"
        stdout.puts "  1. Restart Claude Code to load the new configuration"
        stdout.puts "  2. Use Claude Code normally - transcripts will be ingested automatically"
        stdout.puts "  3. Run 'claude-memory promote <fact_id>' to move facts to global"
        stdout.puts "  4. Run 'claude-memory doctor' to verify setup"

        0
      end

      def init_global
        stdout.puts "Initializing ClaudeMemory (global only)...\n\n"

        manager = ClaudeMemory::Store::StoreManager.new
        manager.ensure_global!
        stdout.puts "✓ Created global database: #{manager.global_db_path}"
        manager.close

        configure_global_hooks
        configure_global_mcp
        configure_global_memory

        stdout.puts "\n=== Global Setup Complete ===\n"
        stdout.puts "ClaudeMemory is now configured globally."
        stdout.puts "\nNote: Run 'claude-memory init' in each project for project-specific memory."

        0
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
        existing["hooks"].merge!(hooks_config["hooks"])

        File.write(settings_path, JSON.pretty_generate(existing))
        stdout.puts "✓ Configured hooks in #{settings_path}"
      end

      def configure_global_mcp
        mcp_path = File.join(Dir.home, ".claude.json")

        existing = load_json_file(mcp_path)
        existing["mcpServers"] ||= {}
        existing["mcpServers"]["claude-memory"] = {
          "type" => "stdio",
          "command" => "claude-memory",
          "args" => ["serve-mcp"]
        }

        File.write(mcp_path, JSON.pretty_generate(existing))
        stdout.puts "✓ Configured MCP server in #{mcp_path}"
      end

      def configure_global_memory
        global_claude_dir = File.join(Dir.home, ".claude")
        claude_md_path = File.join(global_claude_dir, "CLAUDE.md")

        memory_instruction = <<~MD
          # ClaudeMemory

          ClaudeMemory is installed globally. Use these MCP tools:
          - `memory.recall` - Search for relevant facts
          - `memory.explain` - Get detailed fact provenance
          - `memory.conflicts` - Show open contradictions
          - `memory.status` - Check system health
        MD

        FileUtils.mkdir_p(global_claude_dir)
        if File.exist?(claude_md_path)
          content = File.read(claude_md_path)
          unless content.include?("ClaudeMemory")
            File.write(claude_md_path, content + "\n\n" + memory_instruction)
          end
        else
          File.write(claude_md_path, memory_instruction)
        end

        stdout.puts "✓ Updated #{claude_md_path}"
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
        existing["hooks"].merge!(hooks_config["hooks"])

        File.write(settings_path, JSON.pretty_generate(existing))
        stdout.puts "✓ Configured hooks in #{settings_path}"
      end

      def configure_project_mcp
        mcp_path = ".claude.json"

        existing = load_json_file(mcp_path)
        existing["mcpServers"] ||= {}
        existing["mcpServers"]["claude-memory"] = {
          "type" => "stdio",
          "command" => "claude-memory",
          "args" => ["serve-mcp"]
        }

        File.write(mcp_path, JSON.pretty_generate(existing))
        stdout.puts "✓ Configured MCP server in #{mcp_path}"
      end

      def install_output_style
        style_source = File.join(__dir__, "../../output_styles/claude_memory.json")
        style_dest = ".claude/output_styles/claude_memory.json"

        return unless File.exist?(style_source)

        FileUtils.mkdir_p(File.dirname(style_dest))
        FileUtils.cp(style_source, style_dest)
        stdout.puts "✓ Installed output style at #{style_dest}"
      end

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
    end
  end
end
