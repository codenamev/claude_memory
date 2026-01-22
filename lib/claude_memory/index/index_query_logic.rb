# frozen_string_literal: true

module ClaudeMemory
  module Index
    module IndexQueryLogic
      # Pure function: collects fact IDs from provenance records
      # No I/O, no side effects - fully testable
      #
      # @param provenance_by_content [Hash] Map of content_item_id => array of provenance records
      # @param content_ids [Array<Integer>] Content IDs in FTS relevance order
      # @param limit [Integer] Maximum number of fact IDs to collect
      # @return [Array<Integer>] Ordered, deduplicated fact IDs
      def self.collect_fact_ids(provenance_by_content, content_ids, limit)
        return [] if limit <= 0
        return [] if content_ids.empty?

        seen_fact_ids = Set.new
        ordered_fact_ids = []

        content_ids.each do |content_id|
          provenance_records = provenance_by_content[content_id]
          next unless provenance_records

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
    end
  end
end
