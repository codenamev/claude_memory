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
      when "ingest"
        ingest
      when "search"
        search
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
          ingest     Ingest transcript delta
          search     Search indexed content
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

    def ingest
      opts = parse_ingest_options
      return 1 unless opts

      store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
      ingester = ClaudeMemory::Ingest::Ingester.new(store)

      result = ingester.ingest(
        source: opts[:source],
        session_id: opts[:session_id],
        transcript_path: opts[:transcript_path]
      )

      case result[:status]
      when :ingested
        @stdout.puts "Ingested #{result[:bytes_read]} bytes (content_id: #{result[:content_id]})"
      when :no_change
        @stdout.puts "No new content to ingest"
      end

      store.close
      0
    rescue ClaudeMemory::Ingest::TranscriptReader::FileNotFoundError => e
      @stderr.puts "Error: #{e.message}"
      1
    end

    def parse_ingest_options
      opts = {source: "claude_code", db: ClaudeMemory::DEFAULT_DB_PATH}

      parser = OptionParser.new do |o|
        o.banner = "Usage: claude-memory ingest [options]"
        o.on("--source SOURCE", "Source identifier (default: claude_code)") { |v| opts[:source] = v }
        o.on("--session-id ID", "Session identifier (required)") { |v| opts[:session_id] = v }
        o.on("--transcript-path PATH", "Path to transcript file (required)") { |v| opts[:transcript_path] = v }
        o.on("--db PATH", "Database path") { |v| opts[:db] = v }
      end

      parser.parse!(@args[1..])

      unless opts[:session_id] && opts[:transcript_path]
        @stderr.puts parser.help
        @stderr.puts "\nError: --session-id and --transcript-path are required"
        return nil
      end

      opts
    end

    def search
      query = @args[1]
      unless query
        @stderr.puts "Usage: claude-memory search <query> [--db PATH] [--limit N]"
        return 1
      end

      opts = {db: ClaudeMemory::DEFAULT_DB_PATH, limit: 10}
      OptionParser.new do |o|
        o.on("--db PATH", "Database path") { |v| opts[:db] = v }
        o.on("--limit N", Integer, "Max results") { |v| opts[:limit] = v }
      end.parse!(@args[2..])

      store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
      fts = ClaudeMemory::Index::LexicalFTS.new(store)

      ids = fts.search(query, limit: opts[:limit])
      if ids.empty?
        @stdout.puts "No results found."
      else
        @stdout.puts "Found #{ids.size} result(s):"
        ids.each do |id|
          text = store.execute("SELECT raw_text FROM content_items WHERE id = ?", [id]).first&.first
          preview = text&.slice(0, 100)&.gsub(/\s+/, " ")
          @stdout.puts "  [#{id}] #{preview}..."
        end
      end

      store.close
      0
    end
  end
end
