# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Generates embeddings for facts that don't have them yet
    class IndexCommand < BaseCommand
      SCOPE_ALL = "all"
      SCOPE_GLOBAL = "global"
      SCOPE_PROJECT = "project"

      def call(args)
        opts = parse_options(args, {scope: SCOPE_ALL, batch_size: 100, force: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory index [options]"
            parser.on("--scope SCOPE", "Scope: global, project, or all (default: all)") { |v| o[:scope] = v }
            parser.on("--batch-size SIZE", Integer, "Batch size (default: 100)") { |v| o[:batch_size] = v }
            parser.on("--force", "Re-index facts that already have embeddings") { o[:force] = true }
          end
        end
        return 1 if opts.nil?

        unless valid_scope?(opts[:scope])
          stderr.puts "Invalid scope: #{opts[:scope]}"
          stderr.puts "Valid scopes: global, project, all"
          return 1
        end

        generator = Embeddings::Generator.new

        if opts[:scope] == SCOPE_ALL || opts[:scope] == SCOPE_GLOBAL
          index_database("global", Configuration.global_db_path, generator, opts)
        end

        if opts[:scope] == SCOPE_ALL || opts[:scope] == SCOPE_PROJECT
          index_database("project", Configuration.project_db_path, generator, opts)
        end

        0
      end

      private

      def index_database(label, db_path, generator, opts)
        unless File.exist?(db_path)
          stdout.puts "#{label.capitalize} database not found, skipping..."
          return
        end

        store = Store::SQLiteStore.new(db_path)

        # Find facts to index
        facts = if opts[:force]
          store.facts.all
        else
          store.facts.where(embedding_json: nil).all
        end

        if facts.empty?
          stdout.puts "#{label.capitalize} database: All facts already indexed"
          store.close
          return
        end

        stdout.puts "#{label.capitalize} database: Indexing #{facts.size} facts..."

        processed = 0
        facts.each_slice(opts[:batch_size]) do |batch|
          batch.each do |fact|
            # Generate text representation
            text = build_fact_text(fact, store)

            # Generate embedding
            embedding = generator.generate(text)

            # Store embedding
            store.update_fact_embedding(fact[:id], embedding)

            processed += 1
          end

          stdout.puts "  Processed #{processed} / #{facts.size} facts..."
        end

        stdout.puts "  Done!"
        store.close
      end

      def build_fact_text(fact, store)
        # Build rich text representation for embedding
        parts = []

        # Subject
        if fact[:subject_entity_id]
          subject = store.entities.where(id: fact[:subject_entity_id]).first
          parts << subject[:canonical_name] if subject
        end

        # Predicate
        parts << fact[:predicate]

        # Object
        if fact[:object_entity_id]
          object_entity = store.entities.where(id: fact[:object_entity_id]).first
          parts << object_entity[:canonical_name] if object_entity
        elsif fact[:object_literal]
          parts << fact[:object_literal]
        end

        parts.join(" ")
      end

      def valid_scope?(scope)
        [SCOPE_ALL, SCOPE_GLOBAL, SCOPE_PROJECT].include?(scope)
      end
    end
  end
end
