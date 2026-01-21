# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Value object representing a session identifier
    # Provides type safety and validation for session IDs
    class SessionId
      attr_reader :value

      def initialize(value)
        @value = value.to_s
        validate!
        freeze
      end

      def to_s
        value
      end

      def ==(other)
        other.is_a?(SessionId) && other.value == value
      end

      alias_method :eql?, :==

      def hash
        value.hash
      end

      private

      def validate!
        raise ArgumentError, "Session ID cannot be empty" if value.empty?
      end
    end
  end
end
