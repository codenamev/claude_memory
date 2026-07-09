# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # One-time recovery for facts that were superseded because of an
    # obsolete single-value predicate classification. See
    # Sweep::Maintenance#restore_multi_value_supersessions for the algorithm
    # and Jaccard heuristic.
    class RestoreCommand < BaseCommand
      # @param args [Array<String>] command line arguments (--predicate, --scope, --dry-run)
      # @return [Integer] exit code (0 for success, 1 for failure)
      def call(args)
        opts = parse_options(args, {predicate: nil, scope: "project", dry_run: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory restore --predicate NAME [options]"
            parser.on("--predicate NAME", "Predicate to restore (e.g. uses_framework)") { |v| o[:predicate] = v }
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
            parser.on("--dry-run", "Show what would be restored without writing") { o[:dry_run] = true }
          end
        end
        return 1 if opts.nil?

        return failure("--predicate required (e.g. --predicate uses_framework)") if opts[:predicate].nil?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])

        begin
          result = Sweep::HistoricalCleanup.new(store).restore_multi_value_supersessions(
            predicate: opts[:predicate],
            dry_run: opts[:dry_run]
          )
        rescue ArgumentError => e
          stderr.puts e.message
          manager.close
          return 1
        ensure
          manager.close
        end

        print_result(opts, result)
        0
      end

      private

      # Print a summary of restored and skipped facts.
      # @param opts [Hash] parsed options including :predicate, :scope, :dry_run
      # @param result [Hash] result from Sweep::Maintenance#restore_multi_value_supersessions
      # @return [void]
      def print_result(opts, result)
        mode = opts[:dry_run] ? "DRY RUN" : "RESTORE"
        stdout.puts "#{mode}: predicate=#{opts[:predicate]} scope=#{opts[:scope]}"
        stdout.puts "=" * 50
        stdout.puts "Inspected:         #{result[:inspected]}"
        stdout.puts "Restored:          #{result[:restored]}"
        stdout.puts "Skipped ambiguous: #{result[:skipped_ambiguous]}"

        return if result[:decisions].empty?

        stdout.puts
        stdout.puts "Decisions:"
        result[:decisions].each do |d|
          case d[:action]
          when :restore
            stdout.puts "  [restore] ##{d[:fact_id]}  #{d[:object]}"
          when :skip_ambiguous
            overlaps = d[:overlaps_with].map { |o| "'#{o}'" }.join(", ")
            stdout.puts "  [skip]    ##{d[:fact_id]}  #{d[:object]}  (overlaps: #{overlaps})"
          end
        end
      end
    end
  end
end
