# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure logic for collecting and ordering fact IDs from provenance records
    # Follows Functional Core pattern - no I/O, just transformations
    class FactCollector
      # Collect fact IDs from provenance records, maintaining content order and deduplicating
      # @param provenance_by_content [Hash] Map of content_id => array of provenance records with :fact_id
      # @param content_ids [Array<Integer>] Ordered content IDs
      # @param limit [Integer] Maximum fact IDs to collect
      # @return [Array<Integer>] Ordered, deduplicated fact IDs
      def self.collect_ordered_fact_ids(provenance_by_content, content_ids, limit)
        return [] if limit <= 0

        seen_fact_ids = Set.new
        ordered_fact_ids = []

        content_ids.each do |content_id|
          provenance_records = provenance_by_content[content_id] || []

          provenance_records.each do |prov|
            fact_id = prov[:fact_id]
            next if seen_fact_ids.include?(fact_id)

            seen_fact_ids.add(fact_id)
            ordered_fact_ids << fact_id
            break if ordered_fact_ids.size >= limit
          end
          break if ordered_fact_ids.size >= limit
        end

        ordered_fact_ids
      end

      # Extract unique fact IDs from array of provenance records
      # @param provenance_records [Array<Hash>] Records with :fact_id
      # @return [Array<Integer>] Unique fact IDs
      def self.extract_fact_ids(provenance_records)
        provenance_records.map { |p| p[:fact_id] }.uniq
      end

      # Extract unique content IDs from array of provenance records
      # @param provenance_records [Array<Hash>] Records with :content_item_id
      # @return [Array<Integer>] Unique content IDs
      def self.extract_content_ids(provenance_records)
        provenance_records.map { |p| p[:content_item_id] }.uniq
      end
    end
  end
end
