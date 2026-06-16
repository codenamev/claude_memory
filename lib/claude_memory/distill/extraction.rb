# frozen_string_literal: true

module ClaudeMemory
  module Distill
    class Extraction
      attr_reader :entities, :facts, :decisions, :signals, :observations

      def initialize(entities: [], facts: [], decisions: [], signals: [], observations: [])
        @entities = entities
        @facts = facts
        @decisions = decisions
        @signals = signals
        @observations = observations
      end

      def empty?
        entities.empty? && facts.empty? && decisions.empty? && signals.empty? && observations.empty?
      end

      def to_h
        {
          entities: entities,
          facts: facts,
          decisions: decisions,
          signals: signals,
          observations: observations
        }
      end
    end
  end
end
