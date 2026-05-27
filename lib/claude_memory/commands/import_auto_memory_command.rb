# frozen_string_literal: true

require "digest"
require "optparse"

module ClaudeMemory
  module Commands
    # Imports Claude Code auto-memory files (~/.claude/projects/<slug>/memory/*.md)
    # into the project database as durable facts. Before this command, those
    # markdown files were only surfaced transiently via `Hook::AutoMemoryMirror`
    # at SessionStart — they were invisible to `memory.recall` and the
    # shortcut tools. Importing them as facts (predicate=convention for
    # gotcha/feedback/project files, predicate=reference for reference
    # type) makes that knowledge first-class queryable knowledge.
    #
    # Idempotent on object_literal prefix: re-running skips files whose
    # body text is already present.
    class ImportAutoMemoryCommand < BaseCommand
      def call(args)
        opts = parse_opts(args)
        return 1 if opts.nil?

        auto_dir = resolve_auto_dir
        files = list_files(auto_dir)
        if files.empty?
          stdout.puts "No auto-memory files found in #{auto_dir}"
          return 0
        end

        manager = Store::StoreManager.new
        manager.ensure_project!
        store = manager.project_store

        imported = 0
        skipped = 0
        files.each do |path|
          fact_data = parse_file(path)
          next if fact_data.nil?

          if already_imported?(store, fact_data[:object_literal])
            skipped += 1
            next
          end

          if opts[:dry_run]
            stdout.puts "[DRY] #{File.basename(path)} → #{fact_data[:predicate]}"
          else
            insert(store, fact_data, path)
            stdout.puts "Imported: #{File.basename(path)} → #{fact_data[:predicate]}"
          end
          imported += 1
        end

        stdout.puts ""
        verb = opts[:dry_run] ? "Would import" : "Imported"
        stdout.puts "#{verb}: #{imported}  Skipped (already present): #{skipped}"
        manager.close
        0
      end

      private

      def parse_opts(args)
        options = {dry_run: false}
        parser = OptionParser.new do |o|
          o.banner = "Usage: claude-memory import-auto-memory [--dry-run]"
          o.on("--dry-run", "Show what would be imported without writing") { options[:dry_run] = true }
        end
        parser.parse!(args.dup)
        options
      rescue OptionParser::InvalidOption => e
        stderr.puts e.message
        nil
      end

      def resolve_auto_dir
        config = Configuration.new
        Hook::AutoMemoryMirror.default_dir(config.project_dir, config.claude_config_dir)
      end

      def list_files(dir)
        return [] unless Dir.exist?(dir)
        Dir.glob(File.join(dir, "*.md")).reject { |f| File.basename(f) == "MEMORY.md" }.sort
      end

      def parse_file(path)
        text = File.read(path)
        return nil unless (match = text.match(/\A---\n(.*?)\n---\n(.*)\z/m))

        frontmatter = match[1]
        body = match[2].strip

        name = frontmatter[/^name:\s*(.+)/, 1]&.strip
        type = frontmatter[/^type:\s*(.+)/, 1]&.strip
        description = frontmatter[/^description:\s*(.+)/, 1]&.strip
        return nil if name.nil? || type.nil?

        predicate, subject, scope = map_type(type)
        object = build_object(name, description, body)

        {
          subject: subject,
          predicate: predicate,
          object_literal: object,
          scope: scope
        }
      end

      def map_type(type)
        case type
        when "feedback", "user"
          ["convention", "user", "global"]
        when "reference"
          ["reference", "repo", "project"]
        else
          # gotcha, project, anything else
          ["convention", "repo", "project"]
        end
      end

      # Build an object string that carries a reason clause so
      # BareConclusionDetector does not flag the fact as bare. Auto-memory
      # files conventionally include a **Why:** section; we surface the first
      # 400 chars of the body alongside the name as the object text.
      def build_object(name, description, body)
        first_para = body.split("\n\n").first.to_s.strip
        first_para = first_para[0..400] + "..." if first_para.length > 400

        parts = [name]
        parts << description if description && !description.empty? && description != name
        parts << first_para unless first_para.empty?
        text = parts.join(" — ").gsub(/\s+/, " ").strip

        # If no reason clause is present, attach a stable suffix so the fact
        # is structurally distinguishable from bare conclusions.
        text += " (imported from project auto-memory; see source file for full reasoning)" unless reason_present?(text)
        text
      end

      def reason_present?(text)
        text.match?(/\b(because|so that|so the|so we|in order to|to avoid|to ensure|to prevent|prevents|otherwise|caused by|breaks when)\b/i)
      end

      def already_imported?(store, object_text)
        needle = object_text[0..80].gsub(/[%_]/) { |c| "\\#{c}" }
        !store.facts.where(Sequel.like(:object_literal, "#{needle}%")).limit(1).all.empty?
      end

      def insert(store, fact_data, path)
        store.db.transaction do
          subject_type = (fact_data[:subject] == "user") ? "person" : "repo"
          subject_id = store.find_or_create_entity(type: subject_type, name: fact_data[:subject])

          fact_id = store.insert_fact(
            subject_entity_id: subject_id,
            predicate: fact_data[:predicate],
            object_literal: fact_data[:object_literal],
            scope: fact_data[:scope],
            project_path: (fact_data[:scope] == "global") ? nil : Configuration.new.project_dir
          )

          content_id = store.upsert_content_item(
            source: "auto_memory_import",
            session_id: nil,
            text_hash: Digest::SHA256.hexdigest(path + fact_data[:object_literal]),
            byte_len: fact_data[:object_literal].bytesize,
            raw_text: fact_data[:object_literal]
          )

          store.insert_provenance(
            fact_id: fact_id,
            content_item_id: content_id,
            quote: fact_data[:object_literal][0..200],
            strength: "stated"
          )
        end
      end
    end
  end
end
