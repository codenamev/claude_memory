# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Core
    # SessionStart context-injection token budget: the p50/p95/avg of the
    # `context_tokens` recorded on successful hook_context activity events.
    #
    # A pure value object — callers query their own events and pass either the
    # raw detail_json strings (.from_detail_json) or already-extracted token
    # counts (.new). Percentiles come from Core::Percentile.
    class TokenBudget
      TOKEN_KEY = "context_tokens"

      # Build from raw detail_json strings, keeping positive-integer
      # context_tokens. Malformed JSON raises (callers decide how to handle) —
      # detail_json is system-written and expected to be valid.
      def self.from_detail_json(json_values)
        tokens = json_values.filter_map do |json|
          next unless json
          value = JSON.parse(json)[TOKEN_KEY]
          value if value.is_a?(Integer) && value > 0
        end
        new(tokens)
      end

      # @return [Array<Integer>] the token counts, sorted ascending (frozen)
      attr_reader :sorted

      def initialize(tokens)
        @sorted = tokens.sort.freeze
        freeze
      end

      def empty?
        @sorted.empty?
      end

      def sample_size
        @sorted.size
      end

      def p50
        Percentile.of(@sorted, 0.50)
      end

      def p95
        Percentile.of(@sorted, 0.95)
      end

      def avg
        return 0 if empty?
        (@sorted.sum.to_f / @sorted.size).round
      end

      def min
        return 0 if empty?
        @sorted.first
      end

      def max
        return 0 if empty?
        @sorted.last
      end
    end
  end
end
