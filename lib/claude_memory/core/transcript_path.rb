# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Value object representing a transcript file path
    # Provides type safety and validation for file paths
    class TranscriptPath
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
        other.is_a?(TranscriptPath) && other.value == value
      end

      alias_method :eql?, :==

      def hash
        value.hash
      end

      private

      def validate!
        raise ArgumentError, "Transcript path cannot be empty" if value.empty?
      end
    end
  end
end
