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
        existing = @db[:content_fts].where(content_item_id: content_item_id).get(:content_item_id)
        return if existing

        @db[:content_fts].insert(content_item_id: content_item_id, text: text)
      end

      def search(query, limit: 20)
        return [] if query.nil? || query.strip.empty?

        @db[:content_fts]
          .where(Sequel.lit("text MATCH ?", query))
          .order(:rank)
          .limit(limit)
          .select_map(:content_item_id)
      end

      private

      def ensure_fts_table!
        @db.run(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS content_fts 
          USING fts5(content_item_id UNINDEXED, text, tokenize='porter unicode61')
        SQL
      end
    end
  end
end
