# frozen_string_literal: true

module ClaudeMemory
  class Recall
    # Detects when FTS results are strong enough to skip vector search
    # Follows Functional Core pattern - no I/O, pure decision logic
    #
    # When FTS5 returns a strong top match with significant gap to the
    # second result, vector search adds little value and can be skipped.
    # This saves 2-3 seconds on exact keyword matches.
    module ExpansionDetector
      # Minimum number of FTS results needed to evaluate signal strength
      MIN_RESULTS = 2

      # Thresholds for strong FTS signal detection
      # Score is normalized relative to best match (0-1 scale)
      STRONG_TOP_SCORE = 0.85
      MIN_GAP = 0.15

      # Check if FTS results indicate a strong exact match
      # @param fts_ranks [Array<Hash>] FTS results with :rank values (more negative = better)
      # @return [Boolean] true if vector search can be skipped
      def self.strong_fts_signal?(fts_ranks)
        return false if fts_ranks.nil? || fts_ranks.size < MIN_RESULTS

        # FTS5 rank values are negative (more negative = better match)
        # Convert to positive scores for threshold comparison
        scores = fts_ranks.map { |r| -r[:rank].to_f }

        # Normalize to 0-1 range
        max_score = scores.max
        return false if max_score <= 0

        normalized = scores.map { |s| s / max_score }

        top_score = normalized[0]
        second_score = normalized[1]
        gap = top_score - second_score

        top_score >= STRONG_TOP_SCORE && gap >= MIN_GAP
      end
    end
  end
end
