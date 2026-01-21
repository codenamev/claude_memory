# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Commands
    # Handles hook entrypoints (ingest, sweep, publish)
    class HookCommand < BaseCommand
      def call(args)
        subcommand = args.first

        unless subcommand
          stderr.puts "Usage: claude-memory hook <ingest|sweep|publish> [options]"
          stderr.puts "\nReads hook payload JSON from stdin."
          return 1
        end

        unless %w[ingest sweep publish].include?(subcommand)
          stderr.puts "Unknown hook command: #{subcommand}"
          stderr.puts "Available: ingest, sweep, publish"
          return 1
        end

        opts = parse_options(args[1..-1] || [], {db: ClaudeMemory.project_db_path}) do |o|
          OptionParser.new do |parser|
            parser.on("--db PATH", "Database path") { |v| o[:db] = v }
          end
        end
        return 1 if opts.nil?

        payload = parse_hook_payload
        return 1 unless payload

        store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
        handler = ClaudeMemory::Hook::Handler.new(store)

        case subcommand
        when "ingest"
          hook_ingest(handler, payload)
        when "sweep"
          hook_sweep(handler, payload)
        when "publish"
          hook_publish(handler, payload)
        end

        store.close
        0
      rescue ClaudeMemory::Hook::Handler::PayloadError => e
        stderr.puts "Payload error: #{e.message}"
        1
      end

      private

      def parse_hook_payload
        input = stdin.read
        JSON.parse(input)
      rescue JSON::ParserError => e
        stderr.puts "Invalid JSON payload: #{e.message}"
        nil
      end

      def hook_ingest(handler, payload)
        result = handler.ingest(payload)

        case result[:status]
        when :ingested
          stdout.puts "Ingested #{result[:bytes_read]} bytes (content_id: #{result[:content_id]})"
        when :no_change
          stdout.puts "No new content to ingest"
        when :skipped
          stdout.puts "Skipped ingestion: #{result[:reason]}"
        end
      end

      def hook_sweep(handler, payload)
        result = handler.sweep(payload)
        stats = result[:stats]

        stdout.puts "Sweep complete:"
        stdout.puts "  Elapsed: #{stats[:elapsed_seconds].round(2)}s"
        stdout.puts "  Budget honored: #{stats[:budget_honored]}"
      end

      def hook_publish(handler, payload)
        result = handler.publish(payload)

        case result[:status]
        when :updated
          stdout.puts "Published snapshot to #{result[:path]}"
        when :unchanged
          stdout.puts "No changes - #{result[:path]} is up to date"
        end
      end
    end
  end
end
