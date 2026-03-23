# frozen_string_literal: true

module ClaudeMemory
  class Recall
    SCOPE_PROJECT = "project"
    SCOPE_GLOBAL = "global"
    SCOPE_ALL = "all"

    class << self
      def recent_decisions(manager, limit: 10)
        Shortcuts.for(:decisions, manager, limit: limit)
      end

      def architecture_choices(manager, limit: 10)
        Shortcuts.for(:architecture, manager, limit: limit)
      end

      def conventions(manager, limit: 20)
        Shortcuts.for(:conventions, manager, limit: limit)
      end

      def project_config(manager, limit: 10)
        Shortcuts.for(:project_config, manager, limit: limit)
      end
    end

    def initialize(store_or_manager, fts: nil, project_path: nil, env: ENV, embedding_generator: nil)
      config = Configuration.new(env)
      resolved_project_path = project_path || config.project_dir
      resolved_generator = embedding_generator || Embeddings.resolve(env: env)

      @engine = if store_or_manager.is_a?(Store::StoreManager)
        DualEngine.new(
          store_or_manager,
          embedding_generator: resolved_generator,
          project_path: resolved_project_path
        )
      else
        LegacyEngine.new(
          store_or_manager,
          fts: fts || Index::LexicalFTS.new(store_or_manager),
          embedding_generator: resolved_generator,
          project_path: resolved_project_path
        )
      end
    end

    def query(query_text, limit: 10, scope: SCOPE_ALL, include_raw_text: false)
      @engine.query(query_text, limit: limit, scope: scope, include_raw_text: include_raw_text)
    end

    def query_index(query_text, limit: 20, scope: SCOPE_ALL)
      @engine.query_index(query_text, limit: limit, scope: scope)
    end

    def fact_graph(fact_id, depth: 2, scope: nil)
      @engine.fact_graph(fact_id, depth: depth, scope: scope)
    end

    def explain(fact_id_or_docid, scope: nil)
      @engine.explain(fact_id_or_docid, scope: scope)
    end

    def changes(since:, limit: 50, scope: SCOPE_ALL)
      @engine.changes(since: since, limit: limit, scope: scope)
    end

    def conflicts(scope: SCOPE_ALL)
      @engine.conflicts(scope: scope)
    end

    def facts_by_branch(branch_name, limit: 20, scope: SCOPE_ALL)
      @engine.facts_by_branch(branch_name, limit: limit, scope: scope)
    end

    def facts_by_directory(cwd, limit: 20, scope: SCOPE_ALL)
      @engine.facts_by_directory(cwd, limit: limit, scope: scope)
    end

    def facts_by_tool(tool_name, limit: 20, scope: SCOPE_ALL)
      @engine.facts_by_tool(tool_name, limit: limit, scope: scope)
    end

    def query_semantic(text, limit: 10, scope: SCOPE_ALL, mode: :both, explain: false)
      @engine.query_semantic(text, limit: limit, scope: scope, mode: mode, explain: explain)
    end

    def query_concepts(concepts, limit: 10, scope: SCOPE_ALL)
      raise ArgumentError, "Must provide 2-5 concepts" unless (2..5).cover?(concepts.size)

      @engine.query_concepts(concepts, limit: limit, scope: scope)
    end
  end
end
