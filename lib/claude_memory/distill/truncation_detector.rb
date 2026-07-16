# frozen_string_literal: true

module ClaudeMemory
  module Distill
    # Detects when a span of transcript content is a truncated/capped tool
    # result rather than complete ground truth. Claude Code caps large tool
    # output (notably Read) and leaves a marker like "[Read output capped at
    # 500 lines]" or "[Truncated: 12000 chars]" in the transcript. Facts the
    # distiller extracts from such a fragment are drawn from incomplete
    # content, so they are lower-confidence — the same false-positive class as
    # the documented distiller-hallucination-from-doc-text gotcha.
    #
    # Pure function, no side effects, no disk access. This deliberately does
    # NOT try to recover the full file from disk (as some context managers do):
    # ingest runs after the fact, and the file on disk may have changed since
    # the transcript was recorded, so disk recovery at ingest is temporally
    # unsound. We only detect the marker so callers can flag/deprioritize the
    # fragment.
    #
    # Marker strings are Claude-Code-version-specific and may drift; they are
    # centralized here and covered by a regression spec so a drift is a
    # one-line, test-caught change.
    class TruncationDetector
      # Any one of these substrings marks host-truncated tool output.
      TRUNCATION_PATTERNS = [
        # "[Read output capped at 500 lines]" and variants
        /\[Read output capped at\b/i,
        # Generic "[Truncated: ...]" / "[Truncated ...]" markers
        /\[Truncated[:\s]/i,
        # "[Output truncated ...]" / "... output was truncated"
        /\boutput (?:was )?truncated\b/i,
        # "... N lines omitted ...", "(1234 characters truncated)"
        /\b\d[\d,]*\s+(?:lines|characters|chars|bytes)\s+(?:omitted|truncated)\b/i
      ].freeze

      # @param text [String, nil] a span of transcript / tool-output content
      # @return [Boolean] true when the text carries a truncation marker
      def truncated?(text)
        str = text.to_s
        return false if str.empty?

        TRUNCATION_PATTERNS.any? { |re| str.match?(re) }
      end
    end
  end
end
