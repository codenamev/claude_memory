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
        tracker = Infrastructure::OperationTracker.new(store)

        # Check for existing progress (resumption support)
        checkpoint = tracker.get_checkpoint(operation_type: "index_embeddings", scope: label)
        if checkpoint && !opts[:force]
          stdout.puts "#{label.capitalize} database: Resuming from previous run (processed #{checkpoint[:processed_items]} facts)..."
          resume_from_fact_id = checkpoint[:checkpoint_data][:last_fact_id]
        else
          resume_from_fact_id = nil
        end

        # Find facts to index
        facts_dataset = if opts[:force]
          store.facts
        else
          store.facts.where(embedding_json: nil)
        end

        # If resuming, skip facts we've already processed
        if resume_from_fact_id
          facts_dataset = facts_dataset.where(Sequel.lit("id > ?", resume_from_fact_id))
        end

        facts = facts_dataset.order(:id).all

        if facts.empty? && !checkpoint
          stdout.puts "#{label.capitalize} database: All facts already indexed"
          store.close
          return
        elsif facts.empty? && checkpoint
          # Resume found nothing left to do - mark as completed
          tracker.complete_operation(checkpoint[:operation_id])
          stdout.puts "#{label.capitalize} database: Resumed operation completed (nothing left to index)"
          store.close
          return
        end

        # Start or continue operation tracking
        operation_id = checkpoint ? checkpoint[:operation_id] : tracker.start_operation(
          operation_type: "index_embeddings",
          scope: label,
          total_items: facts.size,
          checkpoint_data: {last_fact_id: nil}
        )

        stdout.puts "#{label.capitalize} database: Indexing #{facts.size} facts..."

        processed = checkpoint ? checkpoint[:processed_items] : 0
        begin
          facts.each_slice(opts[:batch_size]) do |batch|
            # Wrap batch processing in transaction for atomicity
            store.db.transaction do
              batch.each do |fact|
                # Generate text representation
                text = build_fact_text(fact, store)

                # Generate embedding
                embedding = generator.generate(text)

                # Store embedding
                store.update_fact_embedding(fact[:id], embedding)

                processed += 1
              end

              # Update checkpoint after batch commits
              last_fact_id = batch.last[:id]
              tracker.update_progress(
                operation_id,
                processed_items: processed,
                checkpoint_data: {last_fact_id: last_fact_id}
              )
            end

            stdout.puts "  Processed #{processed} facts..."
          end

          # Mark operation as completed
          tracker.complete_operation(operation_id)
          stdout.puts "  Done!"
        rescue => e
          # Mark operation as failed
          tracker.fail_operation(operation_id, e.message)
          stderr.puts "  Failed: #{e.message}"
          raise
        ensure
          store.close
        end
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
