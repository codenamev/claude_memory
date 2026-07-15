# frozen_string_literal: true

module ClaudeMemory
  module Core
    module TokenEstimator
      # Approximation: ~4 characters per token for English text
      # More accurate for Claude's tokenizer than simple word count
      CHARS_PER_TOKEN = 4.0

      # Tokens for a raw character count (no whitespace normalization), ceiling
      # to avoid underestimation. The shared primitive behind the observation
      # layer's token_count fields so the 4-chars/token constant lives in one
      # place.
      def self.from_chars(char_count)
        (char_count / CHARS_PER_TOKEN).ceil
      end

      def self.estimate(text)
        return 0 if text.nil? || text.empty?

        # Normalize whitespace before counting, then defer to from_chars so the
        # 4-chars/token arithmetic lives in exactly one place.
        from_chars(text.strip.gsub(/\s+/, " ").length)
      end

      def self.estimate_fact(fact)
        # Estimate tokens for a fact record
        text = [
          fact[:subject_name],
          fact[:predicate],
          fact[:object_literal]
        ].compact.join(" ")

        estimate(text)
      end
    end
  end
end
