# frozen_string_literal: true

module ClaudeMemory
  module Index
    class LexicalFTS
      def initialize(store)
        @store = store
        @db = store.db
        @fts_table_ensured = false
      end

      def index_content_item(content_item_id, text)
        ensure_fts_table!
        existing = @db[:content_fts].where(content_item_id: content_item_id).get(:content_item_id)
        return if existing

        @db[:content_fts].insert(content_item_id: content_item_id, text: text)
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
        @db[:content_fts]
          .where(Sequel.lit("text MATCH ?", escaped_query))
          .order(:rank)
          .limit(limit)
          .select_map(:content_item_id)
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

      def ensure_fts_table!
        return if @fts_table_ensured

        @db.run(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS content_fts
          USING fts5(content_item_id UNINDEXED, text, tokenize='porter unicode61')
        SQL
        @fts_table_ensured = true
      end
    end
  end
end
