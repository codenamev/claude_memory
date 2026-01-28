# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure business logic for ranking facts by concept similarity
    # Follows Functional Core pattern (Gary Bernhardt) - no I/O, just transformations
    class ConceptRanker
      # Rank facts by average similarity across multiple concepts
      # Only returns facts that match ALL concepts
      # @param concept_results [Array<Array<Hash>>] Array of result arrays, one per concept
      # @param limit [Integer] Maximum results to return
      # @return [Array<Hash>] Ranked results with :fact, :receipts, :source, :similarity, :concept_similarities
      def self.rank_by_concepts(concept_results, limit)
        fact_map = build_fact_map(concept_results)
        multi_concept_facts = filter_by_all_concepts(fact_map, concept_results.size)
        return [] if multi_concept_facts.empty?

        rank_by_average_similarity(multi_concept_facts, limit)
      end

      # Build a map of fact_id => array of result matches from each concept
      def self.build_fact_map(concept_results)
        fact_map = Hash.new { |h, k| h[k] = [] }

        concept_results.each_with_index do |results, concept_idx|
          results.each do |result|
            fact_id = result[:fact][:id]
            fact_map[fact_id] << {
              result: result,
              concept_idx: concept_idx,
              similarity: result[:similarity] || 0.0
            }
          end
        end

        fact_map
      end
      private_class_method :build_fact_map

      # Filter to only facts that appear in ALL concept result sets
      def self.filter_by_all_concepts(fact_map, expected_concept_count)
        fact_map.select do |_fact_id, matches|
          represented_concepts = matches.map { |m| m[:concept_idx] }.uniq
          represented_concepts.size == expected_concept_count
        end
      end
      private_class_method :filter_by_all_concepts

      # Rank multi-concept facts by average similarity score
      def self.rank_by_average_similarity(multi_concept_facts, limit)
        ranked = multi_concept_facts.map do |_fact_id, matches|
          similarities = matches.map { |m| m[:similarity] }
          avg_similarity = similarities.sum / similarities.size.to_f

          # Use the first match for fact and receipts data
          first_match = matches.first[:result]

          {
            fact: first_match[:fact],
            receipts: first_match[:receipts],
            source: first_match[:source],
            similarity: avg_similarity,
            concept_similarities: similarities
          }
        end

        # Sort by average similarity (highest first)
        ranked.sort_by { |r| -r[:similarity] }.take(limit)
      end
      private_class_method :rank_by_average_similarity
    end
  end
end
