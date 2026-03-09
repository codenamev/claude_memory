# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Runs SQLite VACUUM and optional integrity check on memory databases.
    # Reclaims space from deleted/superseded facts and defragments storage.
    class CompactCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {scope: "all", check: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory compact [options]"
            parser.on("--scope SCOPE", %w[all global project],
              "Scope: all (default), global, or project") { |v| o[:scope] = v }
            parser.on("--check", "Run integrity check before compacting") { o[:check] = true }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new

        if opts[:scope] == "all" || opts[:scope] == "global"
          compact_database("global", manager.global_db_path, check: opts[:check])
        end

        if opts[:scope] == "all" || opts[:scope] == "project"
          compact_database("project", manager.project_db_path, check: opts[:check])
        end

        manager.close
        0
      end

      private

      def compact_database(label, db_path, check: false)
        unless File.exist?(db_path)
          stdout.puts "#{label}: database not found at #{db_path}"
          return
        end

        size_before = File.size(db_path)

        if check
          stdout.puts "#{label}: running integrity check..."
          result = run_integrity_check(db_path)
          unless result == "ok"
            stderr.puts "#{label}: integrity check failed: #{result}"
            return
          end
          stdout.puts "#{label}: integrity check passed"
        end

        stdout.puts "#{label}: rebuilding FTS index..."
        rebuild_fts(db_path)

        stdout.puts "#{label}: compacting..."
        run_vacuum(db_path)

        size_after = File.size(db_path)
        saved = size_before - size_after

        stdout.puts "#{label}: #{format_size(size_before)} -> #{format_size(size_after)} (#{format_saved(saved)})"
      end

      def rebuild_fts(db_path)
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        fts = ClaudeMemory::Index::LexicalFTS.new(store)
        fts.rebuild!
        store.close
      end

      def run_vacuum(db_path)
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        store.db.run("VACUUM")
        store.close
      end

      def run_integrity_check(db_path)
        store = ClaudeMemory::Store::SQLiteStore.new(db_path)
        result = store.db.fetch("PRAGMA integrity_check").first[:integrity_check]
        store.close
        result
      end

      def format_size(bytes)
        if bytes >= 1024 * 1024
          "#{(bytes / (1024.0 * 1024.0)).round(2)} MB"
        else
          "#{(bytes / 1024.0).round(1)} KB"
        end
      end

      def format_saved(bytes)
        if bytes > 0
          "saved #{format_size(bytes)}"
        elsif bytes == 0
          "no change"
        else
          "grew #{format_size(bytes.abs)}"
        end
      end
    end
  end
end
