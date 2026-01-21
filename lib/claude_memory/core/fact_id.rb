# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Value object representing a fact identifier
    # Provides type safety and validation for fact IDs (positive integers)
    class FactId
      attr_reader :value

      def initialize(value)
        @value = value.to_i
        validate!
        freeze
      end

      def to_i
        value
      end

      def to_s
        value.to_s
      end

      def ==(other)
        other.is_a?(FactId) && other.value == value
      end

      alias_method :eql?, :==

      def hash
        value.hash
      end

      private

      def validate!
        raise ArgumentError, "Fact ID must be a positive integer" unless value.positive?
      end
    end
  end
end
