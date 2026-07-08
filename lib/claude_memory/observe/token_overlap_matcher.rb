# frozen_string_literal: true

module ClaudeMemory
  module Observe
    # Default observation-similarity matcher: lexical token-overlap (Jaccard).
    #
    # Deterministic, free, no embedding dependency — so it runs shell-side in
    # the Reflector's sweep pass at no extra cost. Two bodies are "the same
    # sighting" when their significant-word sets overlap past the threshold.
    # This folds the common case (one event re-observed with slightly different
    # wording — "PreCompact hook set." / "PreCompact hook set — the design
    # analog", Jaccard 0.6) while keeping unrelated observations apart (distinct
    # developer statements share ~no content words → Jaccard ~0).
    #
    # It does NOT capture pure synonym paraphrases ("use SQLite" vs "chose
    # SQLite") — no free lexical method can on short text (measured 2026-06-23:
    # tfidf cosine 0.32 for that pair, indistinguishable from unrelated pairs
    # at 0.13). For paraphrase folding, inject a semantic matcher backed by real
    # embeddings: the Reflector accepts any object responding to
    # `similar?(body_a, body_b)`.
    class TokenOverlapMatcher
      DEFAULT_THRESHOLD = 0.5

      # Function words carry no episodic signal; dropping them focuses the
      # overlap on subject/verb content.
      STOPWORDS = %w[
        a an the to of in on at for and or but we i it is are was were be been
        this that these those with as by from into our your their its do does
      ].to_set.freeze

      def initialize(threshold: DEFAULT_THRESHOLD)
        @threshold = threshold
      end

      # @return [Boolean] true when the two bodies are near-duplicate sightings
      def similar?(body_a, body_b)
        a = significant_tokens(body_a)
        b = significant_tokens(body_b)
        Core::Jaccard.score(a, b) >= @threshold
      end

      private

      def significant_tokens(body)
        body.to_s.downcase.scan(/[a-z0-9]+/)
          .reject { |word| word.length < 2 || STOPWORDS.include?(word) }
          .to_set
      end
    end
  end
end
