# frozen_string_literal: true

module ClaudeMemory
  class Shortcuts
    QUERIES = {
      decisions: {
        query: "decision constraint rule requirement",
        scope: :all,
        limit: 10
      },
      architecture: {
        query: "uses framework implements architecture pattern",
        scope: :all,
        limit: 10
      },
      conventions: {
        query: "convention style format pattern prefer",
        scope: :global,
        limit: 20
      },
      project_config: {
        query: "uses requires depends_on configuration",
        scope: :project,
        limit: 10
      }
    }.freeze

    def self.for(shortcut_name, manager, **overrides)
      config = QUERIES.fetch(shortcut_name)
      options = config.merge(overrides)

      recall = Recall.new(manager)
      recall.query(
        options[:query],
        limit: options[:limit],
        scope: options[:scope]
      )
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
