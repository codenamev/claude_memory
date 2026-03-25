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

      # Truncate text to a maximum length with a suffix
      # @param text [String, nil] Text to truncate
      # @param max_length [Integer] Maximum length before truncation
      # @param suffix [String] Suffix to append when truncated
      # @return [String] Truncated text or original if within limit
      def self.truncate(text, max_length, suffix: "...")
        return "" if text.nil?
        return text if text.length <= max_length
        text[0, max_length] + suffix
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
