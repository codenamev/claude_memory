# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Calculates similarity between embedding vectors
    # Uses cosine similarity for comparing normalized vectors
    class Similarity
      # Calculate cosine similarity between two vectors
      # Assumes vectors are already normalized to unit length
      # @param vec_a [Array<Float>] first vector
      # @param vec_b [Array<Float>] second vector
      # @return [Float] similarity score between 0 and 1
      def self.cosine(vec_a, vec_b)
        return 0.0 if vec_a.nil? || vec_b.nil?
        return 0.0 if vec_a.empty? || vec_b.empty?

        # For normalized vectors, cosine similarity is just the dot product
        dot_product = vec_a.zip(vec_b).sum { |a, b| a * b }

        # Clamp to [0, 1] range (handle floating point errors)
        dot_product.clamp(0.0, 1.0)
      end

      # Find top K most similar items
      # @param query_vector [Array<Float>] query embedding
      # @param candidates [Array<Hash>] array of hashes with :embedding key
      # @param k [Integer] number of top results to return
      # @return [Array<Hash>] top K candidates with :similarity scores
      def self.top_k(query_vector, candidates, k)
        return [] if candidates.empty?

        # Calculate similarities and score
        scored = candidates.map do |candidate|
          embedding = candidate[:embedding]
          similarity = cosine(query_vector, embedding)

          {
            candidate: candidate,
            similarity: similarity
          }
        end

        # Sort by similarity (highest first) and take top K
        scored.sort_by { |item| -item[:similarity] }.take(k)
      end

      # Calculate average similarity of a vector to multiple other vectors
      # Useful for multi-concept queries
      # @param query_vector [Array<Float>] query embedding
      # @param target_vectors [Array<Array<Float>>] target embeddings
      # @return [Float] average similarity
      def self.average_similarity(query_vector, target_vectors)
        return 0.0 if target_vectors.empty?

        similarities = target_vectors.map { |vec| cosine(query_vector, vec) }
        similarities.sum / similarities.size.to_f
      end

      # Batch calculate similarities between one query and many candidates
      # More efficient than calling cosine repeatedly
      # @param query_vector [Array<Float>] query embedding
      # @param candidate_vectors [Array<Array<Float>>] candidate embeddings
      # @return [Array<Float>] similarity scores in same order as candidates
      def self.batch_similarities(query_vector, candidate_vectors)
        candidate_vectors.map { |vec| cosine(query_vector, vec) }
      end
    end
  end
end
