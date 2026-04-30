# frozen_string_literal: true

module ClaudeMemory
  module Distill
    # Catches facts that survived distillation without a reason clause.
    # The SessionStart distillation prompt explicitly requires `decision`
    # and `convention` facts to embed the reason ("— because …", "so that
    # …", "to avoid …", "caused by …", "breaks when …"); facts that ship
    # without one are dead weight once they go stale because nobody can
    # recover the original justification by re-reading the row.
    #
    # This detector is the production-side mirror of that prompt
    # constraint. It exists so the dashboard can quantify how many facts
    # are slipping through the prompt's reason-clause requirement —
    # higher bare-conclusion ratio means the LLM is producing low-quality
    # extractions, which is a hallucination-rate proxy worth surfacing.
    #
    # Pure function, no side effects, safe to call in tight loops.
    class BareConclusionDetector
      # Predicates the prompt requires reasons for. Other predicates
      # (uses_framework, uses_database, etc.) carry their meaning in the
      # subject-predicate-object shape itself, so a bare object is fine.
      GUARDED_PREDICATES = %w[decision convention].freeze

      # Reason-clause signals lifted from the distill-transcripts skill
      # prompt plus a small set of common natural-language variants. The
      # match is case-insensitive and substring-anchored — any one signal
      # qualifies the fact as "explained" even without an em dash.
      REASON_PATTERNS = [
        /\bbecause\b/i,
        /\bso\s+that\b/i,
        /\bso\s+the\b/i,
        /\bso\s+we\b/i,
        /\bin\s+order\s+to\b/i,
        /\bto\s+avoid\b/i,
        /\bto\s+prevent\b/i,
        /\bto\s+ensure\b/i,
        /\bto\s+support\b/i,
        /\bto\s+allow\b/i,
        /\bto\s+enable\b/i,
        /\bto\s+make\b/i,
        /\bto\s+fix\b/i,
        /\bto\s+handle\b/i,
        /\bcaused\s+by\b/i,
        /\bbreaks\s+when\b/i,
        /\bdue\s+to\b/i,
        /\botherwise\b/i,
        /\bwithout\s+(?:which|this|it)\b/i
      ].freeze

      # Returns true when the fact has a guarded predicate AND its object
      # text shows no reason-clause signal. Returns false for any fact
      # outside the guarded predicates so the metric isn't polluted by
      # legitimately-bare facts (uses_database "sqlite" doesn't need a
      # rationale embedded in its object).
      #
      # @param fact [Hash] with :predicate and :object_literal keys (or
      #   :predicate / :object — accepts both shapes used in the codebase)
      # @return [Boolean]
      def bare_conclusion?(fact)
        predicate = fact[:predicate].to_s
        return false unless GUARDED_PREDICATES.include?(predicate)

        object = (fact[:object_literal] || fact[:object]).to_s
        return false if object.empty?

        REASON_PATTERNS.none? { |re| object.match?(re) }
      end
    end
  end
end
