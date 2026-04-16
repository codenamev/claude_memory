# frozen_string_literal: true

module ClaudeMemory
  # Query interface for facts across dual databases (global + project).
  # Delegates to DualEngine or LegacyEngine depending on the store type.
  class Recall
    # @return [String] query only project-scoped facts
    SCOPE_PROJECT = "project"
    # @return [String] query only global-scoped facts
    SCOPE_GLOBAL = "global"
    # @return [String] query both project and global facts (default)
    SCOPE_ALL = "all"

    class << self
      # @param manager [Store::StoreManager] dual-database manager
      # @param limit [Integer] max results
      # @return [Array<Hash>] recent decision facts
      def recent_decisions(manager, limit: 10)
        Shortcuts.for(:decisions, manager, limit: limit)
      end

      # @param manager [Store::StoreManager] dual-database manager
      # @param limit [Integer] max results
      # @return [Array<Hash>] architecture-related facts
      def architecture_choices(manager, limit: 10)
        Shortcuts.for(:architecture, manager, limit: limit)
      end

      # @param manager [Store::StoreManager] dual-database manager
      # @param limit [Integer] max results
      # @return [Array<Hash>] convention facts
      def conventions(manager, limit: 20)
        Shortcuts.for(:conventions, manager, limit: limit)
      end

      # @param manager [Store::StoreManager] dual-database manager
      # @param limit [Integer] max results
      # @return [Array<Hash>] project configuration facts
      def project_config(manager, limit: 10)
        Shortcuts.for(:project_config, manager, limit: limit)
      end
    end

    # @param store_or_manager [Store::SQLiteStore, Store::StoreManager] database store or dual-database manager
    # @param fts [Index::LexicalFTS, nil] full-text search index (used only with legacy single-store)
    # @param project_path [String, nil] project root path (defaults to Configuration#project_dir)
    # @param env [Hash] environment variables
    # @param embedding_generator [Object, nil] vector embedding generator for semantic search
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

    # Search facts by text query using FTS5
    # @param query_text [String] search terms
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @param include_raw_text [Boolean] include source content text in results
    # @param intent [String, nil] query intent hint for ranking
    # @return [Array<Hash>] matching facts with provenance
    def query(query_text, limit: 10, scope: SCOPE_ALL, include_raw_text: false, intent: nil)
      @engine.query(query_text, limit: limit, scope: scope, include_raw_text: include_raw_text, intent: intent)
    end

    # Search content items (not facts) via FTS5 index
    # @param query_text [String] search terms
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @param intent [String, nil] query intent hint for ranking
    # @return [Array<Hash>] matching content items
    def query_index(query_text, limit: 20, scope: SCOPE_ALL, intent: nil)
      @engine.query_index(query_text, limit: limit, scope: scope, intent: intent)
    end

    # Traverse fact relationships (supersessions, conflicts) as a graph
    # @param fact_id [Integer] starting fact ID
    # @param depth [Integer] traversal depth
    # @param scope [String, nil] optional scope filter
    # @return [Hash] graph with nodes and edges
    def fact_graph(fact_id, depth: 2, scope: nil)
      @engine.fact_graph(fact_id, depth: depth, scope: scope)
    end

    # Show provenance chain for a fact
    # @param fact_id_or_docid [Integer, String] fact ID or document ID
    # @param scope [String, nil] optional scope filter
    # @return [Hash] provenance details including source content
    def explain(fact_id_or_docid, scope: nil)
      @engine.explain(fact_id_or_docid, scope: scope)
    end

    # List facts created or modified since a given time
    # @param since [String] ISO 8601 timestamp
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @return [Array<Hash>] recently changed facts
    def changes(since:, limit: 50, scope: SCOPE_ALL)
      @engine.changes(since: since, limit: limit, scope: scope)
    end

    # List open fact conflicts
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @return [Array<Hash>] unresolved conflicts
    def conflicts(scope: SCOPE_ALL)
      @engine.conflicts(scope: scope)
    end

    # Find facts associated with a git branch
    # @param branch_name [String] git branch name
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @return [Array<Hash>] facts from the given branch
    def facts_by_branch(branch_name, limit: 20, scope: SCOPE_ALL)
      @engine.facts_by_branch(branch_name, limit: limit, scope: scope)
    end

    # Find facts associated with a working directory
    # @param cwd [String] directory path
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @return [Array<Hash>] facts from the given directory
    def facts_by_directory(cwd, limit: 20, scope: SCOPE_ALL)
      @engine.facts_by_directory(cwd, limit: limit, scope: scope)
    end

    # Find facts associated with a specific tool
    # @param tool_name [String] tool name (e.g., "Read", "Bash")
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @return [Array<Hash>] facts from sessions using the given tool
    def facts_by_tool(tool_name, limit: 20, scope: SCOPE_ALL)
      @engine.facts_by_tool(tool_name, limit: limit, scope: scope)
    end

    # Search facts using vector embeddings (semantic similarity)
    # @param text [String] natural language query
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @param mode [Symbol] :vector, :lexical, or :both (hybrid RRF)
    # @param explain [Boolean] include scoring breakdown in results
    # @param intent [String, nil] query intent hint for ranking
    # @return [Array<Hash>] semantically similar facts
    def query_semantic(text, limit: 10, scope: SCOPE_ALL, mode: :both, explain: false, intent: nil)
      @engine.query_semantic(text, limit: limit, scope: scope, mode: mode, explain: explain, intent: intent)
    end

    # Find facts at the intersection of multiple concepts
    # @param concepts [Array<String>] 2-5 concept terms to intersect
    # @param limit [Integer] max results
    # @param scope [String] one of SCOPE_ALL, SCOPE_PROJECT, SCOPE_GLOBAL
    # @return [Array<Hash>] facts matching all given concepts
    # @raise [ArgumentError] if concepts count is not 2-5
    def query_concepts(concepts, limit: 10, scope: SCOPE_ALL)
      raise ArgumentError, "Must provide 2-5 concepts" unless (2..5).cover?(concepts.size)

      @engine.query_concepts(concepts, limit: limit, scope: scope)
    end
  end
end
