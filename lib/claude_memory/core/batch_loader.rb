# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Utility for batch loading records from Sequel datasets
    # Eliminates duplication of batch query patterns
    class BatchLoader
      # Load multiple records by IDs and organize them by a key
      #
      # @param dataset [Sequel::Dataset] The dataset to query
      # @param ids [Array] The IDs to load
      # @param group_by [Symbol] How to organize results (:single for hash by ID, or column name for grouping)
      # @return [Hash] Results organized by the specified key
      def self.load_many(dataset, ids, group_by: :id)
        return {} if ids.empty?

        results = dataset.where(id: ids).all

        case group_by
        when :single
          # Single record per ID (hash by ID)
          results.each_with_object({}) { |row, hash| hash[row[:id]] = row }
        when Symbol
          # Multiple records per key (grouped)
          results.group_by { |row| row[group_by] }
        else
          raise ArgumentError, "Invalid group_by: #{group_by.inspect}"
        end
      end
    end
  end
end
