# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Generates embeddings for facts that don't have them yet
    class IndexCommand < BaseCommand
      SCOPE_ALL = "all"
      SCOPE_GLOBAL = "global"
      SCOPE_PROJECT = "project"

      def call(args)
        opts = parse_options(args, {scope: SCOPE_ALL, batch_size: 100, force: false, vec: false, provider: nil}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory index [options]"
            parser.on("--scope SCOPE", "Scope: global, project, or all (default: all)") { |v| o[:scope] = v }
            parser.on("--batch-size SIZE", Integer, "Batch size (default: 100)") { |v| o[:batch_size] = v }
            parser.on("--force", "Re-index facts that already have embeddings") { o[:force] = true }
            parser.on("--vec", "Backfill vec0 index from existing embeddings (no regeneration)") { o[:vec] = true }
            parser.on("--provider NAME", "Embedding provider: tfidf, fastembed, api") { |v| o[:provider] = v }
          end
        end
        return 1 if opts.nil?

        unless valid_scope?(opts[:scope])
          stderr.puts "Invalid scope: #{opts[:scope]}"
          stderr.puts "Valid scopes: global, project, all"
          return 1
        end

        if opts[:vec]
          return vec_backfill(opts)
        end

        generator = Embeddings.resolve(opts[:provider])

        scopes_for(opts[:scope]).each do |label, db_path|
          index_database(label, db_path, generator, opts)
        end

        0
      end

      private

      def scopes_for(scope)
        config = Configuration.new
        pairs = []
        pairs << ["global", config.global_db_path] if scope == SCOPE_ALL || scope == SCOPE_GLOBAL
        pairs << ["project", config.project_db_path] if scope == SCOPE_ALL || scope == SCOPE_PROJECT
        pairs
      end

      def index_database(label, db_path, generator, opts)
        unless File.exist?(db_path)
          stdout.puts "#{label.capitalize} database not found, skipping..."
          return
        end

        store = Store::SQLiteStore.new(db_path)
        handle_dimension_mismatch(store, generator, label)
        tracker = Infrastructure::OperationTracker.new(store)

        facts, checkpoint = find_facts_to_index(store, tracker, label, opts)
        unless facts
          store.close
          return
        end

        operation_id = checkpoint ? checkpoint[:operation_id] : tracker.start_operation(
          operation_type: "index_embeddings",
          scope: label,
          total_items: facts.size,
          checkpoint_data: {last_fact_id: nil}
        )

        stdout.puts "#{label.capitalize} database: Indexing #{facts.size} facts..."
        run_indexing(store, facts, generator, tracker, operation_id, checkpoint, opts)
      end

      # Reconcile the vec0 table's width with the resolved provider before
      # indexing (issue #7, Finding 1). The vec0 width is immutable once the
      # table is created and was only recorded in meta *after* a successful run,
      # so an old tfidf/fresh DB silently created a 384 table and the first
      # non-384 insert hard-failed. We detect the table's actual width directly
      # (not via the meta, which may be unset) and rebuild when it differs.
      def handle_dimension_mismatch(store, generator, label)
        target = generator.dimensions
        # Record the resolved dimension up front so a fresh table is created at
        # the right width on first insert, not left at the 384 default.
        store.set_meta("embedding_dimensions", target.to_s)
        store.set_meta("embedding_provider", generator.name)

        vec_index = store.vector_index
        return unless vec_index.available?

        actual = vec_index.table_dimensions
        return if actual == target # table already at the right width

        if actual # genuine change: existing facts must re-embed at the new width
          stdout.puts "#{label.capitalize}: Embedding dimensions changed (#{actual} → #{target}), rebuilding vector table..."
          clear_stale_embeddings(store)
        end
        vec_index.recreate!(target)
      end

      def find_facts_to_index(store, tracker, label, opts)
        checkpoint = tracker.get_checkpoint(operation_type: "index_embeddings", scope: label)

        if checkpoint && !opts[:force]
          stdout.puts "#{label.capitalize} database: Resuming from previous run (processed #{checkpoint[:processed_items]} facts)..."
          resume_from_fact_id = checkpoint[:checkpoint_data][:last_fact_id]
        end

        facts_dataset = opts[:force] ? store.facts : store.facts.where(embedding_json: nil)
        facts_dataset = facts_dataset.where(Sequel.lit("id > ?", resume_from_fact_id)) if resume_from_fact_id
        facts = facts_dataset.order(:id).all

        if facts.empty? && !checkpoint
          stdout.puts "#{label.capitalize} database: All facts already indexed"
          return nil
        elsif facts.empty? && checkpoint
          tracker.complete_operation(checkpoint[:operation_id])
          stdout.puts "#{label.capitalize} database: Resumed operation completed (nothing left to index)"
          return nil
        end

        [facts, checkpoint]
      end

      def run_indexing(store, facts, generator, tracker, operation_id, checkpoint, opts)
        vec_index = store.vector_index
        stdout.puts "  sqlite-vec available, dual-writing to vec0 index" if vec_index.available?

        embedding_cache = build_embedding_cache(store)
        cache_hits = 0
        processed = checkpoint ? checkpoint[:processed_items] : 0

        begin
          facts.each_slice(opts[:batch_size]) do |batch|
            cache_hits += process_batch(store, batch, generator, vec_index, embedding_cache)
            processed += batch.size

            tracker.update_progress(
              operation_id,
              processed_items: processed,
              checkpoint_data: {last_fact_id: batch.last[:id]}
            )
            stdout.puts "  Processed #{processed} facts..."
          end

          report_dedup_stats(processed, cache_hits)
          store.set_meta("embedding_dimensions", generator.dimensions.to_s)
          store.set_meta("embedding_provider", generator.name)
          tracker.complete_operation(operation_id)
          stdout.puts "  Done!"
        rescue => e
          tracker.fail_operation(operation_id, e.message)
          stderr.puts "  Failed: #{e.message}"
          raise
        ensure
          store.close
        end
      end

      def process_batch(store, batch, generator, vec_index, embedding_cache)
        cache_hits = 0
        store.db.transaction do
          batch.each do |fact|
            text = build_fact_text(fact, store)
            embedding = embedding_cache[text]
            if embedding
              cache_hits += 1
            else
              embedding = generator.generate(text)
              embedding_cache[text] = embedding
            end
            store.update_fact_embedding(fact[:id], embedding)
            vec_index.insert_embedding(fact[:id], embedding) if vec_index.available?
          end
        end
        cache_hits
      end

      def report_dedup_stats(processed, cache_hits)
        return unless processed > 0

        pct = (cache_hits > 0) ? "#{(cache_hits * 100.0 / processed).round(1)}%" : "0%"
        stdout.puts "  Cache hits: #{cache_hits}/#{processed} (#{pct} dedup)"
      end

      def vec_backfill(opts)
        scopes_for(opts[:scope]).each do |label, db_path|
          unless File.exist?(db_path)
            stdout.puts "#{label.capitalize} database not found, skipping..."
            next
          end

          store = Store::SQLiteStore.new(db_path)
          begin
            vec_index = store.vector_index

            unless vec_index.available?
              stderr.puts "#{label.capitalize}: sqlite-vec not available, cannot backfill"
              next
            end

            total = store.facts.where(vec_indexed_at: nil).where(Sequel.~(embedding_json: nil)).where(status: "active").count
            if total == 0
              stdout.puts "#{label.capitalize} database: All embeddings already in vec0 index"
              next
            end

            stdout.puts "#{label.capitalize} database: Backfilling #{total} facts to vec0..."
            backfilled = 0
            loop do
              count = vec_index.backfill_batch!(limit: opts[:batch_size])
              break if count == 0
              backfilled += count
              stdout.puts "  Backfilled #{backfilled}/#{total}..."
            end
            stdout.puts "  Done! #{backfilled} facts indexed in vec0"
          ensure
            store.close
          end
        end

        0
      end

      def build_embedding_cache(store)
        cache = {}
        store.facts
          .where(status: "active")
          .where(Sequel.~(embedding_json: nil))
          .select(:id, :subject_entity_id, :predicate, :object_entity_id, :object_literal, :embedding_json)
          .each do |fact|
            text = build_fact_text(fact, store)
            cache[text] ||= JSON.parse(fact[:embedding_json])
          end
        cache
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

      def clear_stale_embeddings(store)
        store.facts.where(Sequel.~(embedding_json: nil)).update(embedding_json: nil, vec_indexed_at: nil)
        store.vector_index.clear!
      end

      def valid_scope?(scope)
        [SCOPE_ALL, SCOPE_GLOBAL, SCOPE_PROJECT].include?(scope)
      end
    end
  end
end
