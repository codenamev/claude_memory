# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Core
    # Pure logic for building embedding candidates from fact data
    # Follows Functional Core pattern - no I/O, just transformations
    class EmbeddingCandidateBuilder
      # Parse embeddings and prepare candidates for similarity calculation
      # @param facts_data [Array<Hash>] Fact rows with :embedding_json, :id, etc.
      # @return [Array<Hash>] Candidates with parsed :embedding arrays
      def self.build_candidates(facts_data)
        facts_data.map do |row|
          parse_candidate(row)
        end.compact
      end

      # Parse a single fact row into a candidate
      # @param row [Hash] Fact row with :embedding_json, :id, etc.
      # @return [Hash, nil] Candidate hash or nil if parse fails
      def self.parse_candidate(row)
        embedding = JSON.parse(row[:embedding_json])
        {
          fact_id: row[:id],
          embedding: embedding,
          subject_entity_id: row[:subject_entity_id],
          predicate: row[:predicate],
          object_literal: row[:object_literal],
          scope: row[:scope]
        }
      rescue JSON::ParserError
        nil
      end
    end
  end
end
