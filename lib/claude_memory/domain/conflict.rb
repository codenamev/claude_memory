# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing a conflict between two facts
    class Conflict
      attr_reader :id, :fact_a_id, :fact_b_id, :status, :notes,
        :detected_at, :resolved_at

      def initialize(attributes)
        @id = attributes[:id]
        @fact_a_id = attributes[:fact_a_id]
        @fact_b_id = attributes[:fact_b_id]
        @status = attributes[:status] || "open"
        @notes = attributes[:notes]
        @detected_at = attributes[:detected_at]
        @resolved_at = attributes[:resolved_at]

        validate!
        freeze
      end

      def open?
        status == "open"
      end

      def resolved?
        status == "resolved"
      end

      def to_h
        {
          id: id,
          fact_a_id: fact_a_id,
          fact_b_id: fact_b_id,
          status: status,
          notes: notes,
          detected_at: detected_at,
          resolved_at: resolved_at
        }
      end

      private

      def validate!
        raise ArgumentError, "fact_a_id required" if fact_a_id.nil?
        raise ArgumentError, "fact_b_id required" if fact_b_id.nil?
      end
    end
  end
end
