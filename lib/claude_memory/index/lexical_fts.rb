# frozen_string_literal: true

module ClaudeMemory
  module Index
    class LexicalFTS
      def initialize(store)
        @store = store
        @db = store.db
        ensure_fts_table!
      end

      def index_content_item(content_item_id, text)
        existing = @db.get_first_value(
          "SELECT content_item_id FROM content_fts WHERE content_item_id = ?",
          [content_item_id]
        )
        return if existing

        @db.execute(
          "INSERT INTO content_fts (content_item_id, text) VALUES (?, ?)",
          [content_item_id, text]
        )
      end

      def search(query, limit: 20)
        rows = @db.execute(
          <<~SQL,
            SELECT content_item_id FROM content_fts 
            WHERE text MATCH ? 
            ORDER BY rank 
            LIMIT ?
          SQL
          [query, limit]
        )
        rows.map(&:first)
      end

      private

      def ensure_fts_table!
        @db.execute(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS content_fts 
          USING fts5(content_item_id UNINDEXED, text, tokenize='porter unicode61')
        SQL
      end
    end
  end
end
