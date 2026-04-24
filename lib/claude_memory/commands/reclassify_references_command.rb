# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # One-time cleanup for historical convention facts that are actually
    # descriptions of external projects (LOC counts, star counts, author
    # attributions, "X is a plugin…" templates). The Distill::ReferenceMaterialDetector
    # now guards new writes in ManagementHandlers#store_extraction; this
    # command walks existing rows and retags them to predicate=reference.
    class ReclassifyReferencesCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {scope: "project", dry_run: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory reclassify-references [options]"
            parser.on("--scope SCOPE", %w[project global], "Database scope (default: project)") { |v| o[:scope] = v }
            parser.on("--dry-run", "Show what would be reclassified without writing") { o[:dry_run] = true }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])

        begin
          result = Sweep::Maintenance.new(store).reclassify_references(dry_run: opts[:dry_run])
        ensure
          manager.close
        end

        print_result(opts, result)
        0
      end

      private

      def print_result(opts, result)
        mode = opts[:dry_run] ? "DRY RUN" : "RECLASSIFY"
        stdout.puts "#{mode}: scope=#{opts[:scope]}"
        stdout.puts "=" * 50
        stdout.puts "Active conventions inspected: #{result[:inspected]}"
        stdout.puts "Reclassified as reference:    #{result[:reclassified]}"

        return if result[:decisions].empty?

        stdout.puts
        stdout.puts "Decisions:"
        result[:decisions].each do |d|
          preview = d[:object].to_s[0, 100]
          stdout.puts "  fact ##{d[:fact_id]}  #{preview}#{"…" if d[:object].to_s.length > 100}"
        end
      end
    end
  end
end
