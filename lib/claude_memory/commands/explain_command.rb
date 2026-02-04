# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Explains a fact with provenance and relationships
    class ExplainCommand < BaseCommand
      def call(args)
        identifier = args.first
        unless identifier && !identifier.empty?
          stderr.puts "Usage: claude-memory explain <fact_id|docid> [--scope project|global]"
          return 1
        end

        # Accept integer IDs or 8-char docid strings
        fact_ref = identifier.match?(/\A\d+\z/) ? identifier.to_i : identifier

        opts = parse_options(args[1..] || [], {scope: "project"}) do |o|
          OptionParser.new do |parser|
            parser.on("--scope SCOPE", "Scope: project or global") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        recall = ClaudeMemory::Recall.new(manager)

        explanation = recall.explain(fact_ref, scope: opts[:scope])
        if explanation.is_a?(ClaudeMemory::Core::NullExplanation)
          stderr.puts "Fact #{identifier} not found in #{opts[:scope]} database."
          manager.close
          return 1
        end

        docid = explanation[:fact][:docid]
        label = docid ? "##{docid}" : "##{explanation[:fact][:id]}"
        stdout.puts "Fact #{label} (#{opts[:scope]}):"
        print_fact(explanation[:fact])
        print_receipts(explanation[:receipts])

        if explanation[:supersedes].any?
          stdout.puts "  Supersedes: #{explanation[:supersedes].join(", ")}"
        end
        if explanation[:superseded_by].any?
          stdout.puts "  Superseded by: #{explanation[:superseded_by].join(", ")}"
        end
        if explanation[:conflicts].any?
          stdout.puts "  Conflicts: #{explanation[:conflicts].map { |c| c[:id] }.join(", ")}"
        end

        manager.close
        0
      end

      private

      def print_fact(fact)
        stdout.puts "  #{fact[:predicate]}: #{fact[:object_literal]}"
        stdout.puts "    Status: #{fact[:status]}, Confidence: #{fact[:confidence]}"
      end

      def print_receipts(receipts)
        return if receipts.empty?
        stdout.puts "  Receipts (#{receipts.size}):"
        receipts.each do |r|
          stdout.puts "    - #{r[:quote] || "(no quote)"}"
        end
      end
    end
  end
end
