# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Ingests transcript delta into memory database
    class IngestCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {source: "claude_code", db: ClaudeMemory.project_db_path}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory ingest [options]"
            parser.on("--source SOURCE", "Source identifier (default: claude_code)") { |v| o[:source] = v }
            parser.on("--session-id ID", "Session identifier (required)") { |v| o[:session_id] = v }
            parser.on("--transcript-path PATH", "Path to transcript file (required)") { |v| o[:transcript_path] = v }
            parser.on("--db PATH", "Database path") { |v| o[:db] = v }
          end
        end

        unless opts && opts[:session_id] && opts[:transcript_path]
          stderr.puts "\nError: --session-id and --transcript-path are required"
          return 1
        end

        store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
        ingester = ClaudeMemory::Ingest::Ingester.new(store)

        result = ingester.ingest(
          source: opts[:source],
          session_id: opts[:session_id],
          transcript_path: opts[:transcript_path]
        )

        case result[:status]
        when :ingested
          stdout.puts "Ingested #{result[:bytes_read]} bytes (content_id: #{result[:content_id]})"
        when :no_change, :skipped
          stdout.puts "No new content to ingest"
        end

        store.close
        0
      rescue ClaudeMemory::Ingest::TranscriptReader::FileNotFoundError => e
        stderr.puts "Error: #{e.message}"
        1
      end
    end
  end
end
