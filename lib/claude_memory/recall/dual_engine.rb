# frozen_string_literal: true

module ClaudeMemory
  class Recall
    # Query engine for dual-database mode (StoreManager with global + project DBs).
    # Wraps DualQueryTemplate around shared QueryCore methods.
    class DualEngine
      include QueryCore

      def initialize(manager, embedding_generator:, project_path:)
        @manager = manager
        @embedding_generator = embedding_generator
        @project_path = project_path
      end

      def query(query_text, limit:, scope:, include_raw_text: false, intent: nil)
        effective_query = intent_augmented_query(query_text, intent)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          query_single_store(store, effective_query, limit: limit, source: source, include_raw_text: include_raw_text)
        end
        dedupe_and_sort(results, limit)
      end

      def query_index(query_text, limit:, scope:, intent: nil)
        effective_query = intent_augmented_query(query_text, intent)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          query_index_single_store(store, effective_query, limit: limit, source: source)
        end
        dedupe_and_sort_index(results, limit)
      end

      def fact_graph(fact_id, depth:, scope:)
        scope ||= SCOPE_PROJECT
        store = @manager.store_for_scope(scope)
        Core::FactGraph.build(store, fact_id, depth: depth)
      end

      def explain(fact_id_or_docid, scope:)
        scope ||= SCOPE_PROJECT
        store = @manager.store_for_scope(scope)
        fact_id = resolve_fact_identifier(store, fact_id_or_docid)
        explain_from_store(store, fact_id)
      end

      def changes(since:, limit:, scope:)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          changes = fetch_changes(store, since, limit)
          Core::ResultSorter.annotate_source(changes, source)
        end
        Core::ResultSorter.sort_by_timestamp(results, limit)
      end

      def conflicts(scope:)
        dual_execute(scope: scope) do |store, source|
          conflicts = store.open_conflicts
          Core::ResultSorter.annotate_source(conflicts, source)
        end
      end

      def facts_by_branch(branch_name, limit:, scope:)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          facts_by_context_single(store, :git_branch, branch_name, limit: limit, source: source)
        end
        dedupe_and_sort(results, limit)
      end

      def facts_by_directory(cwd, limit:, scope:)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          facts_by_context_single(store, :cwd, cwd, limit: limit, source: source)
        end
        dedupe_and_sort(results, limit)
      end

      def facts_by_tool(tool_name, limit:, scope:)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          facts_by_tool_single(store, tool_name, limit: limit, source: source)
        end
        dedupe_and_sort(results, limit)
      end

      def query_semantic(text, limit:, scope:, mode:, explain: false, intent: nil)
        effective_text = intent_augmented_query(text, intent)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          query_semantic_single(store, effective_text, limit: limit * 3, mode: mode, source: source, explain: explain,
            skip_fts_shortcut: !intent.nil?)
        end
        dedupe_by_fact_id(results, limit)
      end

      def query_concepts(concepts, limit:, scope:)
        results = dual_execute(scope: scope, limit: limit) do |store, source|
          query_concepts_single(store, concepts, limit: limit * 2, source: source)
        end
        dedupe_by_fact_id(results, limit)
      end

      private

      def dual_execute(scope:, limit: nil, &operation)
        template = DualQueryTemplate.new(@manager)
        template.execute(scope: scope, limit: limit, &operation)
      end
    end
  end
end
