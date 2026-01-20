# frozen_string_literal: true

module ClaudeMemory
  module Resolve
    class PredicatePolicy
      POLICIES = {
        "convention" => {cardinality: :multi, exclusive: false},
        "decision" => {cardinality: :multi, exclusive: false},
        "auth_method" => {cardinality: :single, exclusive: true},
        "uses_database" => {cardinality: :single, exclusive: true},
        "uses_framework" => {cardinality: :single, exclusive: true},
        "deployment_platform" => {cardinality: :single, exclusive: true}
      }.freeze

      DEFAULT_POLICY = {cardinality: :multi, exclusive: false}.freeze

      def self.policy_for(predicate)
        POLICIES.fetch(predicate, DEFAULT_POLICY)
      end

      def self.single?(predicate)
        policy_for(predicate)[:cardinality] == :single
      end

      def self.exclusive?(predicate)
        policy_for(predicate)[:exclusive]
      end
    end
  end
end
