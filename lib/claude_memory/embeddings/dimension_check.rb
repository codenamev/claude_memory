# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Value object that detects embedding dimension mismatches.
    # Returns a Result so the caller decides how to handle mismatches —
    # no hidden side effects like dropping tables.
    class DimensionCheck
      Result = Data.define(:status, :stored, :current)

      # @param store [Store::SQLiteStore] database to check meta against
      # @param provider [#dimensions] embedding provider
      # @return [Result] status is :fresh, :match, or :mismatch
      def self.call(store, provider)
        stored = store.get_meta("embedding_dimensions")&.to_i
        return Result.new(status: :fresh, stored: nil, current: provider.dimensions) unless stored
        return Result.new(status: :match, stored: stored, current: provider.dimensions) if stored == provider.dimensions

        Result.new(status: :mismatch, stored: stored, current: provider.dimensions)
      end
    end
  end
end
