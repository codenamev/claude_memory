# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Reaffirm a fact as still true, resetting its decay clock.
    # Restores expiring/expired facts to active (#14).
    class RatifyCommand < BaseCommand
      # @param args [Array<String>] command line arguments (fact_id_or_docid, --scope)
      # @return [Integer] exit code (0 for success, 1 for failure)
      def call(args)
        opts = parse_options(args, {scope: "project"}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory ratify <fact_id_or_docid> [options]"
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        identifier = args.first
        return failure("Usage: claude-memory ratify <fact_id_or_docid> [options]") if identifier.nil? || identifier.empty?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])

        fact_id = resolve_fact_id(store, identifier)
        unless fact_id
          stderr.puts "Fact '#{identifier}' not found in #{opts[:scope]} database."
          manager.close
          return 1
        end

        result = store.ratify_fact(fact_id)
        manager.close

        if result.nil?
          stderr.puts "Fact ##{fact_id} not found."
          return 1
        end

        unless result[:ratified]
          stderr.puts "Fact ##{fact_id} is #{result[:status]} — only active, expiring, or expired facts can be ratified."
          return 1
        end

        stdout.puts "Ratified fact ##{fact_id} in #{opts[:scope]} database (was #{result[:previous_status]}) — decay clock reset."
        0
      end

      private

      # Accept either a numeric fact id or an 8-char docid hex string.
      # @param store [Store::SQLiteStore] database to look up the fact in
      # @param identifier [String] numeric fact id or hex docid
      # @return [Integer, nil] resolved fact id, or nil if not found
      def resolve_fact_id(store, identifier)
        return identifier.to_i if identifier.match?(/\A\d+\z/)

        row = store.find_fact_by_docid(identifier)
        row ? row[:id] : nil
      end
    end
  end
end
