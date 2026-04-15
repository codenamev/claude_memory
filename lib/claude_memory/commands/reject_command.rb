# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Mark a fact as rejected (e.g. a distiller hallucination).
    # Closes any open conflicts involving the fact.
    class RejectCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {scope: "project", reason: nil}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory reject <fact_id_or_docid> [options]"
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
            parser.on("--reason TEXT", "Why this fact is wrong (recorded in conflict notes)") { |v| o[:reason] = v }
          end
        end
        return 1 if opts.nil?

        identifier = args.first
        return failure("Usage: claude-memory reject <fact_id_or_docid> [options]") if identifier.nil? || identifier.empty?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])

        fact_id = resolve_fact_id(store, identifier)
        unless fact_id
          stderr.puts "Fact '#{identifier}' not found in #{opts[:scope]} database."
          manager.close
          return 1
        end

        result = store.reject_fact(fact_id, reason: opts[:reason])
        manager.close

        if result.nil?
          stderr.puts "Fact ##{fact_id} not found."
          return 1
        end

        stdout.puts "Rejected fact ##{fact_id} in #{opts[:scope]} database."
        stdout.puts "Resolved #{result[:conflicts_resolved]} open conflict(s)." if result[:conflicts_resolved] > 0
        0
      end

      private

      # Accept either a numeric fact id or an 8-char docid hex string.
      def resolve_fact_id(store, identifier)
        return identifier.to_i if identifier.match?(/\A\d+\z/)

        row = store.find_fact_by_docid(identifier)
        row ? row[:id] : nil
      end
    end
  end
end
