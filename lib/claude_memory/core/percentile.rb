# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Nearest-rank percentile of a pre-sorted numeric array.
    #
    # `pct` is a fraction in 0.0..1.0 (e.g. 0.95 for p95). Returns 0 for an
    # empty array. The input must already be sorted ascending.
    module Percentile
      def self.of(sorted, pct)
        return 0 if sorted.empty?

        idx = (sorted.size * pct).ceil - 1
        idx = 0 if idx < 0
        idx = sorted.size - 1 if idx >= sorted.size
        sorted[idx]
      end
    end
  end
end
