# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Jaccard similarity of two sets: |A ∩ B| / |A ∪ B|.
    #
    # Pure set math only — callers own their own tokenization/stopwords, since
    # what counts as a "token" differs by domain (observation prose vs.
    # predicate names). Returns 0.0 when either set is empty (including
    # both-empty, so there is no 0/0).
    module Jaccard
      def self.score(a, b)
        return 0.0 if a.empty? || b.empty?

        union = (a | b).size
        return 0.0 if union.zero?
        (a & b).size.to_f / union
      end
    end
  end
end
