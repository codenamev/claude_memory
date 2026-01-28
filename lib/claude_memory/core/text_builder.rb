# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure logic for building searchable text from structured data
    # Follows Functional Core pattern - no I/O, just transformations
    class TextBuilder
      # Build searchable text from entities, facts, and decisions
      # @param entities [Array<Hash>] Entities with :type and :name
      # @param facts [Array<Hash>] Facts with :subject, :predicate, :object, :quote
      # @param decisions [Array<Hash>] Decisions with :title and :summary
      # @return [String] Concatenated searchable text
      def self.build_searchable_text(entities, facts, decisions)
        parts = []
        entities.each { |e| parts << "#{e[:type]}: #{e[:name]}" }
        facts.each { |f| parts << "#{f[:subject]} #{f[:predicate]} #{f[:object]} #{f[:quote]}" }
        decisions.each { |d| parts << "#{d[:title]} #{d[:summary]}" }
        parts.join(" ").strip
      end

      # Transform hash keys from strings to symbols
      # @param hash [Hash] Hash with string or symbol keys
      # @return [Hash] Hash with symbolized keys
      def self.symbolize_keys(hash)
        hash.transform_keys(&:to_sym)
      end
    end
  end
end
