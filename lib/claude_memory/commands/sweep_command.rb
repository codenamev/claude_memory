# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Runs maintenance and pruning on memory database
    class SweepCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {budget: 5, scope: "project"}) do |o|
          OptionParser.new do |parser|
            parser.on("--budget SECONDS", Integer, "Time budget in seconds") { |v| o[:budget] = v }
            parser.on("--scope SCOPE", "Scope: project or global") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])
        sweeper = ClaudeMemory::Sweep::Sweeper.new(store)

        stdout.puts "Running sweep on #{opts[:scope]} database with #{opts[:budget]}s budget..."
        stats = sweeper.run!(budget_seconds: opts[:budget])

        stdout.puts "Sweep complete:"
        stdout.puts "  Proposed facts expired: #{stats[:proposed_facts_expired]}"
        stdout.puts "  Disputed facts expired: #{stats[:disputed_facts_expired]}"
        stdout.puts "  Orphaned provenance deleted: #{stats[:orphaned_provenance_deleted]}"
        stdout.puts "  Old content pruned: #{stats[:old_content_pruned]}"
        stdout.puts "  Elapsed: #{stats[:elapsed_seconds].round(2)}s"
        stdout.puts "  Budget honored: #{stats[:budget_honored]}"

        manager.close
        0
      end
    end
  end
end
