# frozen_string_literal: true

module ClaudeMemory
  module Distill
    class Extraction
      attr_reader :entities, :facts, :decisions, :signals

      def initialize(entities: [], facts: [], decisions: [], signals: [])
        @entities = entities
        @facts = facts
        @decisions = decisions
        @signals = signals
      end

      def empty?
        entities.empty? && facts.empty? && decisions.empty? && signals.empty?
      end

      def to_h
        {
          entities: entities,
          facts: facts,
          decisions: decisions,
          signals: signals
        }
      end
    end
  end
end
