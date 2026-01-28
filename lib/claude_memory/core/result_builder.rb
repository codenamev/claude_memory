# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure utility for building fact result hashes from batch-fetched data
    # Follows Functional Core pattern - no I/O, just transformations
    class ResultBuilder
      # Build fact results from batch-fetched facts and receipts
      # @param fact_ids [Array<Integer>] Fact IDs to build results for
      # @param facts_by_id [Hash] Map of fact_id => fact_hash
      # @param receipts_by_fact_id [Hash] Map of fact_id => array of receipts
      # @param source [Symbol] Source identifier (:project, :global, :legacy)
      # @param similarity [Float, nil] Optional similarity score
      # @return [Array<Hash>] Array of result hashes with :fact, :receipts, :source, :similarity
      def self.build_results(fact_ids, facts_by_id:, receipts_by_fact_id:, source:, similarity: nil)
        fact_ids.map do |fact_id|
          fact = facts_by_id[fact_id]
          next unless fact

          result = {
            fact: fact,
            receipts: receipts_by_fact_id[fact_id] || [],
            source: source
          }
          result[:similarity] = similarity if similarity
          result
        end.compact
      end

      # Build results with variable similarity scores
      # @param matches [Array<Hash>] Array of matches with :fact_id and :similarity
      # @param facts_by_id [Hash] Map of fact_id => fact_hash
      # @param receipts_by_fact_id [Hash] Map of fact_id => array of receipts
      # @param source [Symbol] Source identifier
      # @return [Array<Hash>] Array of result hashes with varying similarity scores
      def self.build_results_with_scores(matches, facts_by_id:, receipts_by_fact_id:, source:)
        matches.map do |match|
          fact_id = match[:fact_id] || match[:candidate]&.[](:fact_id)
          next unless fact_id

          fact = facts_by_id[fact_id]
          next unless fact

          {
            fact: fact,
            receipts: receipts_by_fact_id[fact_id] || [],
            source: source,
            similarity: match[:similarity]
          }
        end.compact
      end
    end
  end
end
