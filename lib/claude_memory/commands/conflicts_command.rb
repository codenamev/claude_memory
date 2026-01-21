# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Shows open conflicts in memory
    class ConflictsCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {scope: "all"}) do |o|
          OptionParser.new do |parser|
            parser.on("--scope SCOPE", "Scope: project, global, or all") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        recall = ClaudeMemory::Recall.new(manager)
        conflicts = recall.conflicts(scope: opts[:scope])

        if conflicts.empty?
          stdout.puts "No open conflicts."
        else
          stdout.puts "Open conflicts (#{conflicts.size}):\n\n"
          conflicts.each do |c|
            source_label = c[:source] ? " [#{c[:source]}]" : ""
            stdout.puts "  Conflict ##{c[:id]}: Fact #{c[:fact_a_id]} vs Fact #{c[:fact_b_id]}#{source_label}"
            stdout.puts "    Status: #{c[:status]}, Detected: #{c[:detected_at]}"
            stdout.puts "    Notes: #{c[:notes]}" if c[:notes]
            stdout.puts
          end
        end

        manager.close
        0
      end
    end
  end
end
