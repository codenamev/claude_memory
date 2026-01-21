# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Recalls facts matching a query
    class RecallCommand < BaseCommand
      def call(args)
        query = args.first
        unless query
          stderr.puts "Usage: claude-memory recall <query> [--limit N] [--scope project|global|all]"
          return 1
        end

        opts = parse_options(args[1..-1] || [], {limit: 10, scope: "all"}) do |o|
          OptionParser.new do |parser|
            parser.on("--limit N", Integer, "Max results") { |v| o[:limit] = v }
            parser.on("--scope SCOPE", "Scope: project, global, or all") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        recall = ClaudeMemory::Recall.new(manager)

        results = recall.query(query, limit: opts[:limit], scope: opts[:scope])
        if results.empty?
          stdout.puts "No facts found."
        else
          stdout.puts "Found #{results.size} fact(s):\n\n"
          results.each do |result|
            print_fact(result[:fact], source: result[:source])
            print_receipts(result[:receipts])
            stdout.puts
          end
        end

        manager.close
        0
      end

      private

      def print_fact(fact, source: nil)
        source_label = source ? " [#{source}]" : ""
        stdout.puts "  #{fact[:subject_name]}.#{fact[:predicate]} = #{fact[:object_literal]}#{source_label}"
        stdout.puts "    Status: #{fact[:status]}, Confidence: #{fact[:confidence]}"
        stdout.puts "    Valid: #{fact[:valid_from]} - #{fact[:valid_to] || "present"}"
      end

      def print_receipts(receipts)
        return if receipts.empty?

        stdout.puts "  Receipts:"
        receipts.each do |r|
          quote_preview = r[:quote]&.slice(0, 80)&.gsub(/\s+/, " ")
          stdout.puts "    - [#{r[:strength]}] \"#{quote_preview}...\""
        end
      end
    end
  end
end
