# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing provenance (evidence) for a fact
    class Provenance
      attr_reader :id, :fact_id, :content_item_id, :quote, :strength, :created_at

      def initialize(attributes)
        @id = attributes[:id]
        @fact_id = attributes[:fact_id]
        @content_item_id = attributes[:content_item_id]
        @quote = attributes[:quote]
        @strength = attributes[:strength] || "stated"
        @created_at = attributes[:created_at]

        validate!
        freeze
      end

      def stated?
        strength == "stated"
      end

      def inferred?
        strength == "inferred"
      end

      def to_h
        {
          id: id,
          fact_id: fact_id,
          content_item_id: content_item_id,
          quote: quote,
          strength: strength,
          created_at: created_at
        }
      end

      private

      def validate!
        raise ArgumentError, "fact_id required" if fact_id.nil?
        raise ArgumentError, "content_item_id required" if content_item_id.nil?
      end
    end
  end
end
