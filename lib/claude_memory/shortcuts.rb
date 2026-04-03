# frozen_string_literal: true

module ClaudeMemory
  class Shortcuts
    QUERIES = {
      decisions: {
        query: "decision constraint rule requirement",
        category: "decision",
        scope: "all",
        limit: 10
      },
      architecture: {
        query: "uses framework implements architecture pattern",
        category: "architecture",
        scope: "all",
        limit: 10
      },
      conventions: {
        query: "convention style format pattern prefer",
        category: "convention",
        scope: "global",
        limit: 20
      },
      project_config: {
        query: "uses requires depends_on configuration",
        category: nil,
        scope: "project",
        limit: 10
      }
    }.freeze

    def self.for(shortcut_name, manager, **overrides)
      config = QUERIES.fetch(shortcut_name)
      options = config.merge(overrides)

      # Combine FTS results with category-based results for better coverage
      recall = Recall.new(manager)
      fts_results = recall.query(
        options[:query],
        limit: options[:limit],
        scope: options[:scope]
      )

      category = options[:category]
      return fts_results unless category && manager.respond_to?(:each_store)

      # Fetch facts directly by category from each store
      category_facts = []
      manager.each_store(scope: options[:scope]) do |store, _source|
        category_facts.concat(store.facts_by_category(category, limit: options[:limit]))
      end

      # Merge: wrap category facts in same format as FTS results, dedupe by fact id
      seen_ids = fts_results.map { |r| r[:fact]&.[](:id) }.compact.to_set
      category_facts.each do |cf|
        next if seen_ids.include?(cf[:id])
        seen_ids << cf[:id]
        fts_results << {fact: cf, source: cf[:scope] || "project"}
      end

      fts_results.first(options[:limit])
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
  end
end
