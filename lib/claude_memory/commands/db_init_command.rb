# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Initializes SQLite databases
    class DbInitCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {global: false, project: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory db:init [options]"
            parser.on("--global", "Initialize global database (~/.claude/memory.sqlite3)") { o[:global] = true }
            parser.on("--project", "Initialize project database (.claude/memory.sqlite3)") { o[:project] = true }
          end
        end
        return 1 if opts.nil?

        # If neither flag specified, initialize both
        opts[:global] = true if !opts[:global] && !opts[:project]
        opts[:project] = true if !opts[:global] && !opts[:project]

        manager = ClaudeMemory::Store::StoreManager.new

        if opts[:global]
          manager.ensure_global!
          stdout.puts "Global database initialized at #{manager.global_db_path}"
          stdout.puts "Schema version: #{manager.global_store.schema_version}"
        end

        if opts[:project]
          manager.ensure_project!
          stdout.puts "Project database initialized at #{manager.project_db_path}"
          stdout.puts "Schema version: #{manager.project_store.schema_version}"
        end

        manager.close
        0
      end
    end
  end
end
