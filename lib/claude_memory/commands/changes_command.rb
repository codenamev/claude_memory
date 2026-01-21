# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Shows recent fact changes
    class ChangesCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {since: nil, limit: 20, scope: "all"}) do |o|
          OptionParser.new do |parser|
            parser.on("--since ISO", "Since timestamp") { |v| o[:since] = v }
            parser.on("--limit N", Integer, "Max results") { |v| o[:limit] = v }
            parser.on("--scope SCOPE", "Scope: project, global, or all") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        opts[:since] ||= (Time.now - 86400 * 7).utc.iso8601

        manager = ClaudeMemory::Store::StoreManager.new
        recall = ClaudeMemory::Recall.new(manager)

        changes = recall.changes(since: opts[:since], limit: opts[:limit], scope: opts[:scope])
        if changes.empty?
          stdout.puts "No changes since #{opts[:since]}."
        else
          stdout.puts "Changes since #{opts[:since]} (#{changes.size}):\n\n"
          changes.each do |change|
            source_label = change[:source] ? " [#{change[:source]}]" : ""
            stdout.puts "  [#{change[:id]}] #{change[:predicate]}: #{change[:object_literal]} (#{change[:status]})#{source_label}"
            stdout.puts "    Created: #{change[:created_at]}"
          end
        end

        manager.close
        0
      end
    end
  end
end
