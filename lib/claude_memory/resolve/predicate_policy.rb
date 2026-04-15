# frozen_string_literal: true

module ClaudeMemory
  module Resolve
    class PredicatePolicy
      # Canonical predicate vocabulary. Curated after a multi-project survey
      # of real memory databases under ~/src — predicates with zero facts
      # across every database were pruned; predicates observed in the wild
      # but missing from the policy (architecture, uses_language) were added.
      #
      # - convention / decision: workhorse multi-value predicates
      # - uses_framework / uses_language: multi-value (projects use multiple)
      # - uses_database / deployment_platform / auth_method: single-value,
      #   correctly 1:1 per project in observed data
      # - architecture: multi-value structural knowledge (was implicit)
      POLICIES = {
        "convention" => {cardinality: :multi, exclusive: false},
        "decision" => {cardinality: :multi, exclusive: false},
        "architecture" => {cardinality: :multi, exclusive: false},
        "uses_framework" => {cardinality: :multi, exclusive: false},
        "uses_language" => {cardinality: :multi, exclusive: false},
        "uses_database" => {cardinality: :single, exclusive: true},
        "deployment_platform" => {cardinality: :single, exclusive: true},
        "auth_method" => {cardinality: :single, exclusive: true}
      }.freeze

      DEFAULT_POLICY = {cardinality: :multi, exclusive: false}.freeze

      # Section classification for the published snapshot. Keeps Publish
      # from hard-coding predicate names; adding a new predicate to the
      # policy and the section map in one place updates everything.
      SECTION_MAP = {
        "decision" => :decisions,
        "convention" => :conventions,
        "uses_database" => :constraints,
        "uses_framework" => :constraints,
        "uses_language" => :constraints,
        "deployment_platform" => :constraints,
        "auth_method" => :constraints
        # architecture intentionally falls through to :additional for now
      }.freeze

      def self.known_predicates
        POLICIES.keys
      end

      # Return the snapshot section a predicate belongs to.
      # Respects legacy prefix/suffix patterns (decided_*, *_convention)
      # that pre-date the policy.
      def self.section_for(predicate)
        return :decisions if predicate&.start_with?("decided_")
        return :conventions if predicate&.include?("_convention")
        SECTION_MAP.fetch(predicate, :additional)
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
