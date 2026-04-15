# frozen_string_literal: true

module ClaudeMemory
  module Resolve
    class PredicatePolicy
      POLICIES = {
        # Core predicates (original)
        "convention" => {cardinality: :multi, exclusive: false},
        "decision" => {cardinality: :multi, exclusive: false},
        "auth_method" => {cardinality: :single, exclusive: true},
        "uses_database" => {cardinality: :single, exclusive: true},
        # uses_framework is multi-value: real projects use multiple frameworks
        # (e.g. Rails + Turbo + Tailwind). Historically marked single-value,
        # which caused valid facts to be silently superseded across several
        # project databases — see docs/influence/predicate_retrospective.md.
        "uses_framework" => {cardinality: :multi, exclusive: false},
        "deployment_platform" => {cardinality: :single, exclusive: true},

        # Extended multi-value predicates (accumulate)
        "preference" => {cardinality: :multi, exclusive: false},
        "workflow" => {cardinality: :multi, exclusive: false},
        "dependency" => {cardinality: :multi, exclusive: false},
        "testing_strategy" => {cardinality: :multi, exclusive: false},
        "tool_usage" => {cardinality: :multi, exclusive: false},

        # Extended single-value predicates (conflict detection)
        "primary_language" => {cardinality: :single, exclusive: true},
        "ci_platform" => {cardinality: :single, exclusive: true}
      }.freeze

      DEFAULT_POLICY = {cardinality: :multi, exclusive: false}.freeze

      def self.known_predicates
        POLICIES.keys
      end

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
