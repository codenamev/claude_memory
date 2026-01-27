# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Displays help information for claude-memory CLI
    class HelpCommand < BaseCommand
      def call(_args)
        stdout.puts <<~HELP
          claude-memory - Long-term memory for Claude Code

          Usage: claude-memory <command> [options]

          Commands:
            changes    Show recent fact changes
            conflicts  Show open conflicts
            db:init    Initialize the SQLite database
            doctor     Check system health
            explain    Explain a fact with receipts
            help       Show this help message
            hook       Run hook entrypoints (ingest|sweep|publish)
            init       Initialize ClaudeMemory in a project
            ingest     Ingest transcript delta
            promote    Promote a project fact to global memory
            publish    Publish snapshot to Claude Code memory
            recall     Recall facts matching a query
            search     Search indexed content
            serve-mcp  Start MCP server
            sweep      Run maintenance/pruning
            uninstall  Remove ClaudeMemory configuration
            version    Show version number

          Run 'claude-memory <command> --help' for more information on a command.
        HELP
        0
      end
    end
  end
end
