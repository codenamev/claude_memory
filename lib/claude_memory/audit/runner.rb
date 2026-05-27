# frozen_string_literal: true

module ClaudeMemory
  module Audit
    # Orchestrates the audit: opens a StoreManager, runs every check in
    # CHECK_METHODS, collects findings, computes an exit code.
    #
    # The runner itself is read-only. Suggestions in each Finding name
    # the commands a user (or skill) would run to remediate; the audit
    # never writes.
    class Runner
      CHECK_METHODS = %i[
        open_conflicts
        single_cardinality_multiplicity
        single_cardinality_churn
        distillation_backlog
        shortcut_decision_leak
        shortcut_convention_scope
        duplicate_global_conventions
        bare_conclusion_rate
        project_starvation
        auto_memory_unimported
      ].freeze

      Result = Data.define(:findings, :stats) do
        def errors = findings.select(&:error?)
        def warnings = findings.select(&:warn?)
        def info = findings.select(&:info?)
        def ok? = errors.empty?
        def exit_code = ok? ? 0 : 1
      end

      def initialize(manager: nil)
        @manager = manager || Store::StoreManager.new
      end

      def run
        findings = CHECK_METHODS.flat_map { |method| Checks.public_send(method, @manager) }
        Result.new(findings: findings, stats: collect_stats)
      end

      private

      def collect_stats
        global = @manager.store_if_exists("global")
        project = @manager.store_if_exists("project")
        {
          checks_run: CHECK_METHODS.size,
          global: store_stats(global),
          project: store_stats(project)
        }
      end

      def store_stats(store)
        return nil unless store
        {
          active_facts: store.facts.where(status: "active").count,
          predicate_counts: predicate_distribution(store)
        }
      end

      def predicate_distribution(store)
        store.facts
          .where(status: "active")
          .group_and_count(:predicate)
          .all
          .map { |row| [row[:predicate], row[:count]] }
          .sort_by { |_, c| -c }
          .to_h
      end
    end
  end
end
