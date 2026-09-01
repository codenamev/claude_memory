# frozen_string_literal: true

module ClaudeMemory
  # Predicate-based shortcuts for the three common "give me X" queries that
  # MCP clients (and humans via CLI) expect to be trivially fast and
  # noise-free.
  #
  # Prior implementation did FTS text search ("convention style format
  # pattern prefer") with a hardcoded global-only scope on `conventions`.
  # That produced cross-predicate matches (uses_database rows leaking into
  # the decisions shortcut) and silently dropped every project convention
  # on the floor. Switching to predicate-based filtering at the store level
  # eliminates both classes of bug; the cost is we no longer rank by FTS
  # relevance, but for "list the project's conventions" that's the correct
  # trade.
  class Shortcuts
    SHORTCUTS = {
      decisions: {
        predicates: %w[decision],
        limit: 10
      },
      architecture: {
        # Includes the stack-shaping predicates so an agent asking
        # "what's the architecture?" gets both narrative architecture
        # facts AND the constraints (uses_database, uses_framework, ...).
        # Without these the shortcut returns only freeform architecture
        # facts and the constraints section stays invisible.
        predicates: %w[architecture uses_database uses_framework uses_language deployment_platform auth_method],
        limit: 10
      },
      conventions: {
        predicates: %w[convention],
        limit: 20
      },
      project_config: {
        predicates: %w[uses_database uses_framework uses_language deployment_platform auth_method],
        limit: 10
      }
    }.freeze

    # @param shortcut_name [Symbol] :decisions, :architecture, :conventions, or :project_config
    # @param manager [Store::StoreManager] dual-database manager
    # @param overrides [Hash] :limit override
    # @return [Array<Hash>] result hashes with :fact, :receipts (empty), :source ("project"/"global")
    def self.for(shortcut_name, manager, **overrides)
      config = SHORTCUTS.fetch(shortcut_name)
      limit = overrides[:limit] || config[:limit]
      predicates = config[:predicates]

      collect_facts(manager, predicates, limit)
    end

    def self.decisions(manager, **overrides)
      self.for(:decisions, manager, **overrides)
    end

    def self.architecture(manager, **overrides)
      self.for(:architecture, manager, **overrides)
    end

    def self.conventions(manager, **overrides)
      self.for(:conventions, manager, **overrides)
    end

    def self.project_config(manager, **overrides)
      self.for(:project_config, manager, **overrides)
    end

    # Query both stores for active facts matching the given predicates.
    # Project facts take precedence (returned first); global facts fill
    # any remaining slots up to the limit. Does NOT create missing DBs —
    # callers like activity_logging's "orphan manager" depend on this
    # surface staying read-only when the project DB hasn't been
    # initialized yet.
    def self.collect_facts(manager, predicates, limit)
      project_store = manager.store_if_exists("project")
      global_store = manager.store_if_exists("global")

      project_rows = fetch_active_facts(project_store, predicates, limit)
      global_rows = fetch_active_facts(global_store, predicates, limit)

      results = project_rows.map { |row| {fact: row, receipts: [], source: "project"} } +
        global_rows.map { |row| {fact: row, receipts: [], source: "global"} }

      results.first(limit)
    end

    def self.fetch_active_facts(store, predicates, limit)
      return [] unless store

      Core::FactQueryBuilder.build_facts_dataset(store)
        .where(Sequel[:facts][:predicate] => predicates,
          Sequel[:facts][:status] => %w[active expiring])
        .reverse_order(Sequel[:facts][:id])
        .limit(limit)
        .all
    end
  end
end
