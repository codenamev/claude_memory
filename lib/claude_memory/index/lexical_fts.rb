# frozen_string_literal: true

module ClaudeMemory
  module Index
    class LexicalFTS
      def initialize(store)
        @store = store
        @db = store.db
        @fts_table_ensured = false
        @contentless = nil
      end

      def index_content_item(content_item_id, text)
        ensure_fts_table!
        if contentless?
          existing = @db.fetch("SELECT rowid FROM content_fts WHERE rowid = ?", content_item_id).first
          return if existing
          @db.fetch("INSERT INTO content_fts(rowid, text) VALUES (?, ?)", content_item_id, text).insert
        else
          existing = @db[:content_fts].where(content_item_id: content_item_id).get(:content_item_id)
          return if existing
          @db[:content_fts].insert(content_item_id: content_item_id, text: text)
        end
      end

      def search(query, limit: 20)
        ensure_fts_table!
        return [] if query.nil? || query.strip.empty?

        if query.strip == "*"
          return @db[:content_items]
              .order(Sequel.desc(:id))
              .limit(limit)
              .select_map(:id)
        end

        escaped_query = escape_fts_query(query)
        if contentless?
          @db.fetch(
            "SELECT rowid AS content_item_id FROM content_fts WHERE text MATCH ? ORDER BY rank LIMIT ?",
            escaped_query, limit
          ).map { |row| row[:content_item_id] }
        else
          @db[:content_fts]
            .where(Sequel.lit("text MATCH ?", escaped_query))
            .order(:rank)
            .limit(limit)
            .select_map(:content_item_id)
        end
      end

      # Search returning content IDs with FTS5 BM25 rank values
      # @param query [String] Search query
      # @param limit [Integer] Maximum results
      # @return [Array<Hash>] Results with :content_item_id and :rank
      def search_with_ranks(query, limit: 20)
        ensure_fts_table!
        return [] if query.nil? || query.strip.empty?
        return [] if query.strip == "*"

        escaped_query = escape_fts_query(query)
        if contentless?
          @db.fetch(
            "SELECT rowid AS content_item_id, rank FROM content_fts WHERE text MATCH ? ORDER BY rank LIMIT ?",
            escaped_query, limit
          ).all
        else
          @db[:content_fts]
            .where(Sequel.lit("text MATCH ?", escaped_query))
            .order(:rank)
            .limit(limit)
            .select(Sequel.lit("content_item_id, rank"))
            .all
        end
      end

      # Remove a content item from the FTS index
      def remove_content_item(content_item_id, text)
        ensure_fts_table!
        if contentless?
          @db.fetch(
            "INSERT INTO content_fts(content_fts, rowid, text) VALUES('delete', ?, ?)",
            content_item_id, text
          ).insert
        else
          @db[:content_fts].where(content_item_id: content_item_id).delete
        end
      end

      # Rebuild the entire FTS index from content_items.
      # Always rebuilds as contentless to save space.
      def rebuild!
        @db.run("DROP TABLE IF EXISTS content_fts")
        @fts_table_ensured = false
        @contentless = nil

        create_contentless_table!

        @db[:content_items].select(:id, :raw_text).order(:id).paged_each(rows_per_fetch: 500) do |row|
          @db.fetch(
            "INSERT INTO content_fts(rowid, text) VALUES (?, ?)",
            row[:id], row[:raw_text]
          ).insert
        end
      end

      def escape_fts_query(query)
        words = query.split(/\s+/).map do |word|
          next word if word == "*"
          escaped = word.gsub('"', '""')
          %("#{escaped}")
        end.compact

        return words.first if words.size == 1
        words.join(" OR ")
      end

      private

      def contentless?
        @contentless
      end

      def ensure_fts_table!
        return if @fts_table_ensured

        detect_table_format!
        return if @fts_table_ensured

        # No table exists yet — create contentless
        create_contentless_table!
      end

      def detect_table_format!
        row = @db.fetch("SELECT sql FROM sqlite_master WHERE name = 'content_fts' AND type = 'table'").first
        return unless row

        sql = row[:sql].to_s
        @contentless = sql.include?("content=''")
        @fts_table_ensured = true
      end

      def create_contentless_table!
        @db.run(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS content_fts
          USING fts5(text, content='', tokenize='porter unicode61')
        SQL
        @contentless = true
        @fts_table_ensured = true
      end
    end
  end
end
