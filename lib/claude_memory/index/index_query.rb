# frozen_string_literal: true

module ClaudeMemory
  module Index
    class IndexQuery
      def initialize(store, options)
        @store = store
        @options = options
        @fts = LexicalFTS.new(store)
      end

      def execute
        # Query 1: Search FTS for content IDs (1 query)
        content_ids = search_content

        return [] if content_ids.empty?

        # Query 2: Batch fetch ALL provenance records (1 query, not N!)
        provenance_by_content = fetch_all_provenance(content_ids)

        # Pure logic: collect fact IDs (no I/O)
        fact_ids = IndexQueryLogic.collect_fact_ids(
          provenance_by_content,
          content_ids,
          @options.limit
        )

        return [] if fact_ids.empty?

        # Query 3: Batch fetch facts with entities (1 query, not N!)
        fetch_facts(fact_ids)
      end

      private

      def search_content
        # Fetch 3x limit of content to ensure enough facts after deduplication
        @fts.search(@options.query_text, limit: @options.limit * 3)
      end

      def fetch_all_provenance(content_ids)
        # Batch query: fetch ALL provenance records at once using WHERE IN
        # This replaces N individual queries (one per content_id)
        @store.provenance
          .select(:fact_id, :content_item_id)
          .where(content_item_id: content_ids)
          .all
          .group_by { |p| p[:content_item_id] }
      end

      def fetch_facts(fact_ids)
        # Batch query: fetch ALL facts at once using WHERE IN
        # This replaces N individual queries (one per fact_id)
        @store.facts
          .left_join(:entities, id: :subject_entity_id)
          .select(
            Sequel[:facts][:id],
            Sequel[:facts][:predicate],
            Sequel[:facts][:object_literal],
            Sequel[:facts][:status],
            Sequel[:facts][:scope],
            Sequel[:facts][:confidence],
            Sequel[:entities][:canonical_name].as(:subject_name)
          )
          .where(Sequel[:facts][:id] => fact_ids)
          .all
          .map do |fact|
            {
              id: fact[:id],
              subject: fact[:subject_name],
              predicate: fact[:predicate],
              object_preview: truncate_preview(fact[:object_literal]),
              status: fact[:status],
              scope: fact[:scope],
              confidence: fact[:confidence],
              token_estimate: Core::TokenEstimator.estimate_fact(fact),
              source: @options.source
            }
          end
      end

      def truncate_preview(text)
        return nil if text.nil?
        return text if text.length <= 50
        text[0, 50]
      end
    end
  end
end
