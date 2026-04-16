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
            compact    Compact databases (VACUUM + integrity check)
            conflicts  Show open conflicts
            db:init    Initialize the SQLite database
            doctor     Check system health
            explain    Explain a fact with receipts
            export     Export facts to JSON for backup
            help       Show this help message
            hook       Run hook entrypoints (ingest|sweep|publish|context)
            init       Initialize ClaudeMemory in a project
            ingest     Ingest transcript delta
            promote    Promote a project fact to global memory
            publish    Publish snapshot to Claude Code memory
            recall     Recall facts matching a query
            recover    Recover stuck operations
            reject     Mark a fact as rejected (e.g. hallucination)
            restore    Restore superseded facts from reclassified predicates
            search     Search indexed content
            serve-mcp  Start MCP server
            stats      Show statistics (--tools for MCP telemetry)
            sweep      Run maintenance/pruning
            uninstall  Remove ClaudeMemory configuration
            version    Show version number

          Utilities:
            completion     Generate shell completions (bash/zsh)
            embeddings     Inspect embedding backend
            git-lfs        Git LFS integration for memory DB
            index          Build or rebuild content indexes
            install-skill  Install agent skills to ~/.claude/commands/

          Run 'claude-memory <command> --help' for more information on a command.
        HELP
        0
      end
    end
  end
end
