# frozen_string_literal: true

module ClaudeMemory
  class Recall
    # Template for executing queries across both global and project databases
    # Eliminates duplication of dual-database query patterns
    class DualQueryTemplate
      SCOPE_ALL = "all"
      SCOPE_PROJECT = "project"
      SCOPE_GLOBAL = "global"

      def initialize(manager)
        @manager = manager
      end

      # Execute a query operation across global and/or project stores based on scope
      #
      # @param scope [String] One of: "all", "project", or "global"
      # @param limit [Integer] Maximum results (used by deduplicator, not enforced here)
      # @yield [store, source] Yields each store with its source label
      # @return [Array] Combined results from both stores
      def execute(scope:, limit: nil, &operation)
        results = []

        if should_query_project?(scope)
          results.concat(query_store(:project, &operation))
        end

        if should_query_global?(scope)
          results.concat(query_store(:global, &operation))
        end

        results
      end

      private

      def should_query_project?(scope)
        (scope == SCOPE_ALL || scope == SCOPE_PROJECT) && @manager.project_exists?
      end

      def should_query_global?(scope)
        (scope == SCOPE_ALL || scope == SCOPE_GLOBAL) && @manager.global_exists?
      end

      def query_store(source_label, &operation)
        store = (source_label == :project) ? @manager.project_store : @manager.global_store
        return [] unless store

        ensure_store!(source_label)
        operation.call(store, source_label)
      end

      def ensure_store!(source_label)
        if source_label == :project
          @manager.ensure_project!
        else
          @manager.ensure_global!
        end
      end
    end
  end
end
