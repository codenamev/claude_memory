# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure logic for sorting and limiting result collections
    # Follows Functional Core pattern - no I/O, just transformations
    class ResultSorter
      # Sort results by timestamp (created_at) in descending order and apply limit
      # @param results [Array<Hash>] Results with :created_at keys
      # @param limit [Integer] Maximum results to return
      # @return [Array<Hash>] Sorted, limited results (most recent first)
      def self.sort_by_timestamp(results, limit)
        results.sort_by { |r| r[:created_at] }.reverse.first(limit)
      end

      # Add source annotation to each result in collection
      # @param results [Array<Hash>] Results to annotate
      # @param source [Symbol] Source identifier (:project, :global, :legacy)
      # @return [Array<Hash>] Results with :source key added (mutates in place)
      def self.annotate_source(results, source)
        results.each { |r| r[:source] = source }
      end
    end
  end
end
