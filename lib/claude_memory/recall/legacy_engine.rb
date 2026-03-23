# frozen_string_literal: true

module ClaudeMemory
  class Recall
    # Query engine for legacy single-store mode.
    # Operates directly on one SQLiteStore with local scope filtering.
    class LegacyEngine
      include QueryCore

      def initialize(store, fts:, embedding_generator:, project_path:)
        @store = store
        @fts = fts
        @embedding_generator = embedding_generator
        @project_path = project_path
      end

      def query(query_text, limit:, scope:, include_raw_text: false)
        content_ids = @fts.search(query_text, limit: limit * 3)
        return [] if content_ids.empty?

        provenance_by_content = @store.provenance
          .select(:fact_id, :content_item_id)
          .where(content_item_id: content_ids)
          .all
          .group_by { |p| p[:content_item_id] }

        all_fact_ids = []
        seen_fact_ids = Set.new
        content_ids.each do |content_id|
          (provenance_by_content[content_id] || []).each do |prov|
            next if seen_fact_ids.include?(prov[:fact_id])
            seen_fact_ids.add(prov[:fact_id])
            all_fact_ids << prov[:fact_id]
          end
        end

        return [] if all_fact_ids.empty?

        facts_by_id = batch_find_facts(@store, all_fact_ids)

        selected_fact_ids = []
        all_fact_ids.each do |fact_id|
          fact = facts_by_id[fact_id]
          next unless fact
          next unless fact_matches_scope?(fact, scope)
          selected_fact_ids << fact_id
          break if selected_fact_ids.size >= limit
        end

        return [] if selected_fact_ids.empty?

        receipts_by_fact_id = batch_find_receipts(@store, selected_fact_ids)

        facts_with_provenance = selected_fact_ids.map do |fact_id|
          {
            fact: facts_by_id[fact_id],
            receipts: receipts_by_fact_id[fact_id] || []
          }
        end

        sort_by_scope_priority(facts_with_provenance)
      end

      def query_index(query_text, limit:, scope:)
        options = Index::QueryOptions.new(
          query_text: query_text,
          limit: limit,
          scope: :all,
          source: :legacy
        )

        query = Index::IndexQuery.new(@store, options)
        results = query.execute

        results.select do |result|
          fact = Core::FactQueryBuilder.find_fact(@store, result[:id])
          fact && fact_matches_scope?(fact, scope)
        end
      end

      def fact_graph(fact_id, depth:, scope:)
        Core::FactGraph.build(@store, fact_id, depth: depth)
      end

      def explain(fact_id_or_docid, scope:)
        fact_id = resolve_fact_identifier(@store, fact_id_or_docid)
        explain_from_store(@store, fact_id)
      end

      def changes(since:, limit:, scope:)
        ds = @store.facts
          .select(:id, :docid, :subject_entity_id, :predicate, :object_literal, :status, :created_at, :scope, :project_path)
          .where { created_at >= since }
          .order(Sequel.desc(:created_at))
          .limit(limit)

        ds = apply_scope_filter(ds, scope)
        ds.all
      end

      def conflicts(scope:)
        all_conflicts = @store.open_conflicts
        return all_conflicts if scope == SCOPE_ALL

        all_conflicts.select do |conflict|
          fact_a = Core::FactQueryBuilder.find_fact(@store, conflict[:fact_a_id])
          fact_b = Core::FactQueryBuilder.find_fact(@store, conflict[:fact_b_id])

          fact_matches_scope?(fact_a, scope) || fact_matches_scope?(fact_b, scope)
        end
      end

      def facts_by_branch(branch_name, limit:, scope:)
        facts_by_context_single(@store, :git_branch, branch_name, limit: limit, source: :legacy)
      end

      def facts_by_directory(cwd, limit:, scope:)
        facts_by_context_single(@store, :cwd, cwd, limit: limit, source: :legacy)
      end

      def facts_by_tool(tool_name, limit:, scope:)
        facts_by_tool_single(@store, tool_name, limit: limit, source: :legacy)
      end

      def query_semantic(text, limit:, scope:, mode:, explain: false)
        query_semantic_single(@store, text, limit: limit, mode: mode, source: :legacy, explain: explain)
      end

      def query_concepts(concepts, limit:, scope:)
        query_concepts_single(@store, concepts, limit: limit, source: :legacy)
      end
    end
  end
end
