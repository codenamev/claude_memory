# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Null object pattern for Fact
    # Represents a non-existent fact without using nil
    class NullFact
      def present?
        false
      end

      def to_h
        {
          id: nil,
          subject_name: nil,
          predicate: nil,
          object_literal: nil,
          status: "not_found",
          confidence: 0.0,
          valid_from: nil,
          valid_to: nil
        }
      end

      def [](key)
        to_h[key]
      end
    end
  end
end
