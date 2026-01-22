# frozen_string_literal: true

module ClaudeMemory
  module Core
    class TokenEstimator
      # Approximation: ~4 characters per token for English text
      # More accurate for Claude's tokenizer than simple word count
      CHARS_PER_TOKEN = 4.0

      def self.estimate(text)
        return 0 if text.nil? || text.empty?

        # Remove extra whitespace and count characters
        normalized = text.strip.gsub(/\s+/, " ")
        chars = normalized.length

        # Return ceiling to avoid underestimation
        (chars / CHARS_PER_TOKEN).ceil
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
