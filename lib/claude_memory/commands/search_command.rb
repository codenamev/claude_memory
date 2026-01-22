# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Searches indexed content using full-text search
    class SearchCommand < BaseCommand
      def call(args)
        query = args.first
        unless query
          stderr.puts "Usage: claude-memory search <query> [--db PATH] [--limit N]"
          return 1
        end

        opts = parse_options(args[1..] || [], {limit: 10, scope: "all"}) do |o|
          OptionParser.new do |parser|
            parser.on("--limit N", Integer, "Max results") { |v| o[:limit] = v }
            parser.on("--scope SCOPE", "Scope: project, global, or all") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope((opts[:scope] == "global") ? "global" : "project")
        fts = ClaudeMemory::Index::LexicalFTS.new(store)

        ids = fts.search(query, limit: opts[:limit])
        if ids.empty?
          stdout.puts "No results found."
        else
          stdout.puts "Found #{ids.size} result(s):"
          ids.each do |id|
            text = store.content_items.where(id: id).get(:raw_text)
            preview = text&.slice(0, 100)&.gsub(/\s+/, " ")
            stdout.puts "  [#{id}] #{preview}..."
          end
        end

        manager.close
        0
      end
    end
  end
end
