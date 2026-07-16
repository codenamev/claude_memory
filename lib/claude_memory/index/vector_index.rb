# frozen_string_literal: true

module ClaudeMemory
  module Index
    # Native sqlite-vec KNN search wrapper
    # Follows the same lazy-init pattern as LexicalFTS:
    # the extension and virtual table are created on first use.
    class VectorIndex
      DEFAULT_DIMENSIONS = 384

      attr_reader :dimensions

      def initialize(store)
        @store = store
        @db = store.db
        @available = nil
        @vec_table_ensured = false
        @dimensions = store.get_meta("embedding_dimensions")&.to_i || DEFAULT_DIMENSIONS
      end

      # Is the sqlite-vec extension loadable?
      # Caches the result after the first probe.
      def available?
        return @available unless @available.nil?

        @available = load_extension!
      end

      # Insert (or replace) a fact's embedding into the vec0 virtual table.
      # Also sets vec_indexed_at on the fact row.
      # @param fact_id [Integer]
      # @param vector [Array<Float>] 384-dimensional embedding
      def insert_embedding(fact_id, vector)
        return false unless available?

        ensure_vec_table!
        blob = vector.pack("f*")
        # Atomic: the vec0 row and the fact's vec_indexed_at flag must land
        # together, or an interruption between them drifts the row vs the flag.
        @db.transaction do
          # vec0 doesn't support INSERT OR REPLACE; delete first
          execute_with_params("DELETE FROM facts_vec WHERE fact_id = ?", fact_id)
          execute_with_params(
            "INSERT INTO facts_vec(fact_id, embedding) VALUES (?, ?)",
            fact_id, blob
          )
          @store.facts.where(id: fact_id).update(vec_indexed_at: Time.now.utc.iso8601)
        end
        true
      end

      # Remove a fact's embedding from the vec0 virtual table.
      # Also clears vec_indexed_at on the fact row.
      # @param fact_id [Integer]
      def remove_embedding(fact_id)
        return false unless available?

        ensure_vec_table!
        @db[:facts_vec].where(fact_id: fact_id).delete
        @store.facts.where(id: fact_id).update(vec_indexed_at: nil)
        true
      end

      # KNN search: returns fact_ids + distances, caller hydrates facts
      # Two-step query pattern (no JOINs with vec0).
      # @param query_vector [Array<Float>]
      # @param k [Integer] number of nearest neighbors
      # @return [Array<Hash>] [{fact_id:, distance:, similarity:}, ...]
      def search(query_vector, k: 10)
        return [] unless available?

        ensure_vec_table!
        blob = query_vector.pack("f*")

        rows = @db.synchronize do |conn|
          conn.query(
            "SELECT fact_id, distance FROM facts_vec WHERE embedding MATCH ? AND k = ? ORDER BY distance",
            [blob, k]
          )
        end

        rows.map do |row|
          {
            fact_id: row[:fact_id],
            distance: row[:distance],
            similarity: (1.0 - row[:distance]).clamp(0.0, 1.0)
          }
        end
      end

      # Backfill facts that have embedding_json but haven't been indexed in vec0
      # @param limit [Integer] max facts to process per call
      # @return [Integer] number of facts backfilled
      def backfill_batch!(limit: 100)
        return 0 unless available?

        ensure_vec_table!
        rows = @store.facts
          .where(vec_indexed_at: nil)
          .where(Sequel.~(embedding_json: nil))
          .where(status: "active")
          .select(:id, :embedding_json)
          .order(:id)
          .limit(limit)
          .all

        return 0 if rows.empty?

        now = Time.now.utc.iso8601
        indexed_ids = []

        rows.each do |row|
          vector = JSON.parse(row[:embedding_json])
          blob = vector.pack("f*")
          # No DELETE needed: vec_indexed_at is nil so these rows can't be in vec0
          execute_with_params(
            "INSERT INTO facts_vec(fact_id, embedding) VALUES (?, ?)",
            row[:id], blob
          )
          indexed_ids << row[:id]
        rescue JSON::ParserError
          next
        end

        # Batch-update timestamps
        @store.facts.where(id: indexed_ids).update(vec_indexed_at: now) if indexed_ids.any?

        indexed_ids.size
      end

      # Delete all entries from the vec0 virtual table.
      # Used when clearing stale embeddings after a dimension change.
      def clear!
        return false unless available?

        ensure_vec_table!
        @db.run("DELETE FROM facts_vec")
        true
      end

      # Drop and rebuild facts_vec at `dimensions`. A vec0 column width is
      # immutable once the table is created, so adopting a model of a different
      # dimension (or any model on a DB whose table was created at the 384
      # default) requires a full rebuild — clearing rows isn't enough (issue #7,
      # Finding 1). Requires the sqlite-vec extension loaded so the vec0
      # destructor runs on DROP.
      # @param dimensions [Integer] new embedding width
      def recreate!(dimensions)
        return false unless available?

        @dimensions = dimensions
        @db.run("DROP TABLE IF EXISTS facts_vec")
        @vec_table_ensured = false
        ensure_vec_table!
        true
      end

      # The width facts_vec was actually created with, parsed from its DDL — or
      # nil when the table doesn't exist yet. Detects a stale-width table even
      # when the embedding_dimensions meta was never written (old tfidf DBs),
      # which is exactly the case that silently left a 384 table in place.
      # @return [Integer, nil]
      def table_dimensions
        ddl = @db[:sqlite_master].where(type: "table", name: "facts_vec").get(:sql)
        ddl && ddl[/embedding\s+float\[(\d+)\]/, 1]&.to_i
      end

      # Number of entries in the vec0 virtual table
      def count
        return 0 unless available?

        ensure_vec_table!
        @db[:facts_vec].count
      end

      # Coverage statistics for vec indexing
      # @return [Hash] {with_embedding:, vec_indexed:, coverage_pct:}
      def coverage_stats
        with_embedding = @store.facts.where(Sequel.~(embedding_json: nil)).where(status: "active").count
        vec_indexed = @store.facts.where(Sequel.~(vec_indexed_at: nil)).where(status: "active").count
        coverage_pct = (with_embedding > 0) ? (vec_indexed * 100.0 / with_embedding).round(1) : 0

        {with_embedding: with_embedding, vec_indexed: vec_indexed, coverage_pct: coverage_pct}
      end

      private

      # Execute parameterized SQL via the raw Extralite connection
      # Sequel's db.run doesn't support bind params with Extralite
      def execute_with_params(sql, *params)
        @db.synchronize { |conn| conn.execute(sql, params) }
      end

      def load_extension!
        require "sqlite_vec"
        @db.synchronize do |conn|
          SqliteVec.load(conn)
        end
        true
      rescue LoadError, StandardError
        false
      end

      def ensure_vec_table!
        return if @vec_table_ensured

        @db.run(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS facts_vec
          USING vec0(fact_id INTEGER PRIMARY KEY, embedding float[#{@dimensions}] distance_metric=cosine)
        SQL
        @vec_table_ensured = true
      end
    end
  end
end
