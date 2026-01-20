# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  class CLI
    COMMANDS = %w[help version db:init].freeze

    def initialize(args = ARGV, stdout: $stdout, stderr: $stderr)
      @args = args
      @stdout = stdout
      @stderr = stderr
    end

    def run
      command = @args.first || "help"

      case command
      when "help", "-h", "--help"
        print_help
        0
      when "version", "-v", "--version"
        print_version
        0
      when "db:init"
        db_init
        0
      else
        @stderr.puts "Unknown command: #{command}"
        @stderr.puts "Run 'claude-memory help' for usage."
        1
      end
    end

    private

    def print_help
      @stdout.puts <<~HELP
        claude-memory - Long-term memory for Claude Code

        Usage: claude-memory <command> [options]

        Commands:
          db:init    Initialize the SQLite database
          help       Show this help message
          version    Show version number

        Run 'claude-memory <command> --help' for more information on a command.
      HELP
    end

    def print_version
      @stdout.puts "claude-memory #{ClaudeMemory::VERSION}"
    end

    def db_init
      db_path = @args[1] || ClaudeMemory::DEFAULT_DB_PATH
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      @stdout.puts "Database initialized at #{db_path}"
      @stdout.puts "Schema version: #{store.schema_version}"
      store.close
    end
  end
end
