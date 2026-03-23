# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Reciprocal Rank Fusion (RRF) for merging ranked result lists
    # Follows Functional Core pattern - no I/O, just transformations
    #
    # RRF combines multiple ranked lists using position-based scoring:
    #   score(d) = Σ(weight_r / (k + rank_r(d)))
    #
    # This is more effective than naive deduplication because it considers
    # rank positions from both sources, giving higher scores to results
    # that appear near the top in multiple lists.
    class RRFusion
      K = 60 # Standard RRF constant - controls rank pressure
      TOP_BONUS = {1 => 0.05, 2 => 0.02, 3 => 0.02}.freeze

      # Fuse ranked lists from vector and text search
      # @param vector_results [Array<Hash>] Results from vector search (ordered by similarity)
      # @param text_results [Array<Hash>] Results from text search (ordered by FTS rank)
      # @param limit [Integer] Maximum results to return
      # @param vector_weight [Float] Weight multiplier for vector rankings (default 1.0)
      # @param text_weight [Float] Weight multiplier for text rankings (default 1.0)
      # @return [Array<Hash>] Fused results sorted by RRF score, with :similarity set to RRF score
      def self.fuse(vector_results, text_results, limit, vector_weight: 1.0, text_weight: 1.0, explain: false)
        scores = {}
        traces = {} if explain
        fact_data = {}

        # Score vector results by rank position
        vector_results.each_with_index do |result, idx|
          fact_id = result[:fact][:id]
          rank = idx + 1 # 1-based rank
          contribution = (vector_weight / (K + rank)) + TOP_BONUS.fetch(rank, 0.0)
          scores[fact_id] = (scores[fact_id] || 0.0) + contribution
          if explain
            traces[fact_id] ||= {vec_rank: nil, vec_score: nil, fts_rank: nil, fts_score: nil, vec_rrf: nil, fts_rrf: nil}
            traces[fact_id][:vec_rank] = rank
            traces[fact_id][:vec_score] = result[:similarity]
            traces[fact_id][:vec_rrf] = contribution.round(6)
          end
          # Prefer vector result data (has real similarity score)
          fact_data[fact_id] = result
        end

        # Score text results by rank position
        text_results.each_with_index do |result, idx|
          fact_id = result[:fact][:id]
          rank = idx + 1
          contribution = (text_weight / (K + rank)) + TOP_BONUS.fetch(rank, 0.0)
          scores[fact_id] = (scores[fact_id] || 0.0) + contribution
          if explain
            traces[fact_id] ||= {vec_rank: nil, vec_score: nil, fts_rank: nil, fts_score: nil, vec_rrf: nil, fts_rrf: nil}
            traces[fact_id][:fts_rank] = rank
            traces[fact_id][:fts_score] = result[:similarity]
            traces[fact_id][:fts_rrf] = contribution.round(6)
          end
          # Only use text data if not already present from vector
          fact_data[fact_id] ||= result
        end

        # Sort by RRF score descending and return top results
        scores
          .sort_by { |_id, score| -score }
          .take(limit)
          .map do |fact_id, score|
            merged = fact_data[fact_id].merge(similarity: score)
            merged[:score_trace] = traces[fact_id].merge(rrf_final: score.round(6)) if explain
            merged
          end
      end
    end
  end
end
