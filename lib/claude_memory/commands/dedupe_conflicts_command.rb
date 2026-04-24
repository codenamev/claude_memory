# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # One-time cleanup for historical conflict-row duplication caused by a
    # resolver bug that created a new disputed fact + conflict row each time
    # the same contradicting value was re-extracted (see
    # Resolver#apply_conflict dedupe fix landed 2026-04-24). New conflicts
    # can no longer duplicate this way; this command cleans the tail.
    class DedupeConflictsCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {scope: "project", dry_run: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory dedupe-conflicts [options]"
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
            parser.on("--dry-run", "Show what would be resolved without writing") { o[:dry_run] = true }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])

        begin
          result = Sweep::Maintenance.new(store).dedupe_open_conflicts(dry_run: opts[:dry_run])
        ensure
          manager.close
        end

        print_result(opts, result)
        0
      end

      private

      def print_result(opts, result)
        mode = opts[:dry_run] ? "DRY RUN" : "DEDUPE"
        stdout.puts "#{mode}: scope=#{opts[:scope]}"
        stdout.puts "=" * 50
        stdout.puts "Conflicts inspected: #{result[:inspected]}"
        stdout.puts "Duplicates resolved: #{result[:resolved]}"

        return if result[:decisions].empty?

        stdout.puts
        stdout.puts "Decisions:"
        result[:decisions].each do |d|
          stdout.puts "  conflict ##{d[:conflict_id]} -> merged into ##{d[:keeper_id]} (rejects fact ##{d[:duplicate_fact_id]})"
        end
      end
    end
  end
end
