# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Query construction logic for fact-related database queries
    # Builds Sequel datasets with appropriate joins and selects
    # Follows Functional Core pattern - pure query building, no execution
    class FactQueryBuilder
      # Build dataset for batch finding facts with entity joins
      # @param store [SQLiteStore] Database store
      # @param fact_ids [Array<Integer>] Fact IDs to load
      # @return [Hash] Hash of fact_id => fact_row
      def self.batch_find_facts(store, fact_ids)
        return {} if fact_ids.empty?

        results = build_facts_dataset(store)
          .where(Sequel[:facts][:id] => fact_ids)
          .all

        results.each_with_object({}) { |row, hash| hash[row[:id]] = row }
      end

      # Build dataset for batch finding receipts (provenance) with content_items join
      # @param store [SQLiteStore] Database store
      # @param fact_ids [Array<Integer>] Fact IDs to find receipts for
      # @return [Hash] Hash of fact_id => [receipt_rows]
      def self.batch_find_receipts(store, fact_ids)
        return {} if fact_ids.empty?

        results = build_receipts_dataset(store)
          .where(Sequel[:provenance][:fact_id] => fact_ids)
          .all

        results.group_by { |row| row[:fact_id] }.tap do |grouped|
          # Ensure all requested fact_ids have an entry (empty array if no receipts)
          fact_ids.each { |id| grouped[id] ||= [] }
        end
      end

      # Find single fact by ID with entity join
      # @param store [SQLiteStore] Database store
      # @param fact_id [Integer] Fact ID
      # @return [Hash, nil] Fact row or nil
      def self.find_fact(store, fact_id)
        build_facts_dataset(store)
          .where(Sequel[:facts][:id] => fact_id)
          .first
      end

      # Find receipts for a single fact
      # @param store [SQLiteStore] Database store
      # @param fact_id [Integer] Fact ID
      # @return [Array<Hash>] Receipt rows
      def self.find_receipts(store, fact_id)
        build_receipts_dataset(store)
          .where(Sequel[:provenance][:fact_id] => fact_id)
          .all
      end

      # Find fact IDs that supersede the given fact
      # @param store [SQLiteStore] Database store
      # @param fact_id [Integer] Fact ID
      # @return [Array<Integer>] Fact IDs
      def self.find_superseded_by(store, fact_id)
        store.fact_links
          .where(to_fact_id: fact_id, link_type: "supersedes")
          .select_map(:from_fact_id)
      end

      # Find fact IDs that are superseded by the given fact
      # @param store [SQLiteStore] Database store
      # @param fact_id [Integer] Fact ID
      # @return [Array<Integer>] Fact IDs
      def self.find_supersedes(store, fact_id)
        store.fact_links
          .where(from_fact_id: fact_id, link_type: "supersedes")
          .select_map(:to_fact_id)
      end

      # Find conflicts involving the given fact
      # @param store [SQLiteStore] Database store
      # @param fact_id [Integer] Fact ID
      # @return [Array<Hash>] Conflict rows
      def self.find_conflicts(store, fact_id)
        store.conflicts
          .select(:id, :fact_a_id, :fact_b_id, :status)
          .where(Sequel.or(fact_a_id: fact_id, fact_b_id: fact_id))
          .all
      end

      # Find facts created since a given timestamp
      # @param store [SQLiteStore] Database store
      # @param since [Time, String] Timestamp
      # @param limit [Integer] Maximum results
      # @return [Array<Hash>] Fact rows
      def self.fetch_changes(store, since, limit)
        store.facts
          .select(:id, :subject_entity_id, :predicate, :object_literal, :status, :created_at, :scope, :project_path)
          .where { created_at >= since }
          .order(Sequel.desc(:created_at))
          .limit(limit)
          .all
      end

      # Find provenance records for a content item
      # @param store [SQLiteStore] Database store
      # @param content_id [Integer] Content item ID
      # @return [Array<Hash>] Provenance rows
      def self.find_provenance_by_content(store, content_id)
        store.provenance
          .select(:id, :fact_id, :content_item_id, :quote, :strength)
          .where(content_item_id: content_id)
          .all
      end

      # Build standard facts dataset with entity join and all necessary columns
      # @param store [SQLiteStore] Database store
      # @return [Sequel::Dataset] Configured dataset
      def self.build_facts_dataset(store)
        store.facts
          .left_join(:entities, id: :subject_entity_id)
          .select(
            Sequel[:facts][:id],
            Sequel[:facts][:predicate],
            Sequel[:facts][:object_literal],
            Sequel[:facts][:status],
            Sequel[:facts][:confidence],
            Sequel[:facts][:valid_from],
            Sequel[:facts][:valid_to],
            Sequel[:facts][:created_at],
            Sequel[:entities][:canonical_name].as(:subject_name),
            Sequel[:facts][:scope],
            Sequel[:facts][:project_path]
          )
      end

      # Build standard receipts dataset with content_items join
      # @param store [SQLiteStore] Database store
      # @return [Sequel::Dataset] Configured dataset
      def self.build_receipts_dataset(store)
        store.provenance
          .left_join(:content_items, id: :content_item_id)
          .select(
            Sequel[:provenance][:id],
            Sequel[:provenance][:fact_id],
            Sequel[:provenance][:quote],
            Sequel[:provenance][:strength],
            Sequel[:content_items][:session_id],
            Sequel[:content_items][:occurred_at]
          )
      end
    end
  end
end
