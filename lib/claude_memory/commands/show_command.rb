# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Prints what memory would inject on the next SessionStart.
    #
    # The trust answer to "is this still worth it?" requires
    # inspectability: a user who can't see what memory will inject can't
    # develop confidence in it. The CLAUDE.md alternative is `cat
    # CLAUDE.md` — instant, plain English, no tooling. This command is
    # the same one-line inspect surface for the curated facts the
    # injector picks each session.
    #
    # Runs the exact `Hook::ContextInjector` path real sessions use, so
    # what you see here is what Claude actually receives — not a
    # rebuilt approximation that could drift.
    #
    # The default suppresses the "Pending Knowledge Extraction" dump
    # (which contains raw transcript JSON intended for LLM distillation)
    # so the output stays human-readable. Pass `--pending` to see the
    # full fresh-session payload, including those raw items.
    class ShowCommand < BaseCommand
      VALID_SOURCES = %w[startup resume clear].freeze

      # Any string outside FRESH_SESSION_SOURCES skips the pending-knowledge
      # block. "preview" reads naturally in any debug log this surfaces in.
      NON_FRESH_SOURCE = "preview"

      def call(args)
        opts = parse_options(args, {source: nil, pending: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory show [--source SOURCE] [--pending]"
            parser.on("--source SOURCE", VALID_SOURCES,
              "Simulate fresh-session source (#{VALID_SOURCES.join(", ")}). " \
              "Forces inclusion of pending-knowledge and auto-memory-mirror " \
              "sections regardless of --pending.") { |v| o[:source] = v }
            parser.on("--pending",
              "Include the pending-knowledge dump (raw transcript JSON " \
              "for LLM distillation). Default suppresses it for readability.") { o[:pending] = true }
          end
        end
        return 1 if opts.nil?

        effective_source = opts[:source] || (opts[:pending] ? nil : NON_FRESH_SOURCE)

        manager = Store::StoreManager.new
        manager.ensure_both!
        injector = Hook::ContextInjector.new(manager, source: effective_source)
        context = injector.generate_context

        print_header(opts[:source])
        stdout.puts ""

        if context.nil? || context.strip.empty?
          stdout.puts "_Memory has no facts to inject yet._"
          stdout.puts ""
          stdout.puts "Run a few Claude Code sessions in this project, or use"
          stdout.puts "`memory.store_extraction` from a session to seed facts."
        else
          stdout.puts context
          stdout.puts ""
          print_footer(injector, context)
        end

        manager.close
        0
      rescue Sequel::DatabaseError => e
        failure("Database error: #{e.message}")
      end

      private

      def print_header(source)
        label = source ? " (source=#{source})" : ""
        stdout.puts "## Memory snapshot — would be injected at next SessionStart#{label}"
      end

      def print_footer(injector, context)
        tokens = Core::TokenEstimator.estimate(context)
        fact_count = injector.emitted_fact_ids.size
        stdout.puts "---"
        stdout.puts "#{fact_count} fact#{"s" unless fact_count == 1} • " \
          "~#{tokens} token#{"s" unless tokens == 1} • " \
          "#{context.length} chars"
      end
    end
  end
end
