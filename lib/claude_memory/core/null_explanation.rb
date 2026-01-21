# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Null object pattern for Explanation
    # Represents a non-existent explanation without using nil
    class NullExplanation
      def present?
        false
      end

      def fact
        NullFact.new
      end

      def receipts
        []
      end

      def superseded_by
        []
      end

      def supersedes
        []
      end

      def conflicts
        []
      end

      def to_h
        {
          fact: fact.to_h,
          receipts: receipts,
          superseded_by: superseded_by,
          supersedes: supersedes,
          conflicts: conflicts
        }
      end

      def [](key)
        to_h[key]
      end
    end
  end
end
