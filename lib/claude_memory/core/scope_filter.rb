# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure business logic for scope filtering and matching
    # Follows Functional Core pattern - no I/O, just transformations
    class ScopeFilter
      SCOPE_ALL = "all"
      SCOPE_PROJECT = "project"
      SCOPE_GLOBAL = "global"

      # Check if a fact matches the given scope
      # @param fact [Hash] Fact record with :scope and :project_path
      # @param scope [String] Scope to match against ("all", "project", "global")
      # @param project_path [String] Current project path for project scope matching
      # @return [Boolean] True if fact matches scope
      def self.matches?(fact, scope, project_path)
        return true if scope == SCOPE_ALL

        fact_scope = fact[:scope] || "project"
        fact_project = fact[:project_path]

        case scope
        when SCOPE_PROJECT
          fact_scope == "project" && fact_project == project_path
        when SCOPE_GLOBAL
          fact_scope == "global"
        else
          true
        end
      end

      # Apply scope filter to a Sequel dataset
      # @param dataset [Sequel::Dataset] Dataset to filter
      # @param scope [String] Scope to filter by
      # @param project_path [String] Current project path for project scope
      # @return [Sequel::Dataset] Filtered dataset
      def self.apply_to_dataset(dataset, scope, project_path)
        case scope
        when SCOPE_PROJECT
          dataset.where(scope: "project", project_path: project_path)
        when SCOPE_GLOBAL
          dataset.where(scope: "global")
        else
          dataset
        end
      end

      # Filter array of facts by scope
      # @param facts [Array<Hash>] Facts to filter
      # @param scope [String] Scope to filter by
      # @param project_path [String] Current project path
      # @return [Array<Hash>] Filtered facts
      def self.filter_facts(facts, scope, project_path)
        return facts if scope == SCOPE_ALL

        facts.select { |fact| matches?(fact, scope, project_path) }
      end
    end
  end
end
