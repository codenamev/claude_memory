# frozen_string_literal: true

module ClaudeMemory
  class Recall
    # Shared store-level query logic used by both LegacyEngine and DualEngine.
    # All methods take a `store` parameter — no direct access to @legacy_store or @manager.
    module QueryCore
      private

      def query_single_store(store, query_text, limit:, source:, include_raw_text: false)
        fts = Index::LexicalFTS.new(store)
        content_ids = fts.search(query_text, limit: limit * 3)
        return [] if content_ids.empty?

        provenance_by_content = store.provenance
          .select(:fact_id, :content_item_id)
          .where(content_item_id: content_ids)
          .all
          .group_by { |p| p[:content_item_id] }

        ordered_fact_ids = Core::FactCollector.collect_ordered_fact_ids(
          provenance_by_content,
          content_ids,
          limit
        )

        return [] if ordered_fact_ids.empty?

        facts_by_id = batch_find_facts(store, ordered_fact_ids)
        receipts_by_fact_id = batch_find_receipts(store, ordered_fact_ids, include_raw_text: include_raw_text)

        Core::ResultBuilder.build_results(
          ordered_fact_ids,
          facts_by_id: facts_by_id,
          receipts_by_fact_id: receipts_by_fact_id,
          source: source
        )
      end

      def query_index_single_store(store, query_text, limit:, source:)
        options = Index::QueryOptions.new(
          query_text: query_text,
          limit: limit,
          scope: :all,
          source: source
        )

        query = Index::IndexQuery.new(store, options)
        query.execute
      end

      def facts_by_context_single(store, column, value, limit:, source:)
        content_ids = store.content_items
          .where(column => value)
          .select(:id)
          .map { |row| row[:id] }

        return [] if content_ids.empty?

        fact_ids = store.provenance
          .where(content_item_id: content_ids)
          .select(:fact_id)
          .distinct
          .map { |row| row[:fact_id] }

        return [] if fact_ids.empty?

        facts_by_id = batch_find_facts(store, fact_ids)
        receipts_by_fact_id = batch_find_receipts(store, fact_ids)

        results = Core::ResultBuilder.build_results(
          fact_ids,
          facts_by_id: facts_by_id,
          receipts_by_fact_id: receipts_by_fact_id,
          source: source
        )
        results.take(limit)
      end

      def facts_by_tool_single(store, tool_name, limit:, source:)
        content_ids = store.tool_calls
          .where(tool_name: tool_name)
          .select(:content_item_id)
          .distinct
          .map { |row| row[:content_item_id] }

        return [] if content_ids.empty?

        fact_ids = store.provenance
          .where(content_item_id: content_ids)
          .select(:fact_id)
          .distinct
          .map { |row| row[:fact_id] }

        return [] if fact_ids.empty?

        facts_by_id = batch_find_facts(store, fact_ids)
        receipts_by_fact_id = batch_find_receipts(store, fact_ids)

        results = Core::ResultBuilder.build_results(
          fact_ids,
          facts_by_id: facts_by_id,
          receipts_by_fact_id: receipts_by_fact_id,
          source: source
        )
        results.take(limit)
      end

      def query_semantic_single(store, text, limit:, mode:, source:)
        vector_results = []
        text_results = []

        if mode == :text || mode == :both
          text_results = search_by_fts(store, text, limit, source)
        end

        if mode == :vector || mode == :both
          skip_vector = mode == :both && strong_fts_signal?(store, text)
          vector_results = search_by_vector(store, text, limit, source) unless skip_vector
        end

        merge_search_results(vector_results, text_results, limit)
      end

      def query_concepts_single(store, concepts, limit:, source:)
        concept_results = concepts.map do |concept|
          search_by_vector(store, concept, limit * 5, source)
        end

        Core::ConceptRanker.rank_by_concepts(concept_results, limit)
      end

      # Explain / fact lookup helpers

      def resolve_fact_identifier(store, identifier)
        return identifier if identifier.is_a?(Integer)

        str = identifier.to_s
        return str.to_i if str.match?(/\A\d+\z/)

        fact = Core::FactQueryBuilder.find_fact_by_docid(store, str)
        fact ? fact[:id] : nil
      end

      def explain_from_store(store, fact_id)
        fact = Core::FactQueryBuilder.find_fact(store, fact_id)
        return Core::NullExplanation.new unless fact

        {
          fact: fact,
          receipts: Core::FactQueryBuilder.find_receipts(store, fact_id),
          superseded_by: Core::FactQueryBuilder.find_superseded_by(store, fact_id),
          supersedes: Core::FactQueryBuilder.find_supersedes(store, fact_id),
          conflicts: Core::FactQueryBuilder.find_conflicts(store, fact_id)
        }
      end

      def fetch_changes(store, since, limit)
        Core::FactQueryBuilder.fetch_changes(store, since, limit)
      end

      # Batch helpers

      def batch_find_facts(store, fact_ids)
        Core::FactQueryBuilder.batch_find_facts(store, fact_ids)
      end

      def batch_find_receipts(store, fact_ids, include_raw_text: false)
        Core::FactQueryBuilder.batch_find_receipts(store, fact_ids, include_raw_text: include_raw_text)
      end

      # Vector search helpers

      def search_by_vector(store, query_text, limit, source)
        query_embedding = @embedding_generator.generate(query_text)

        vec_index = store.vector_index
        if vec_index.available?
          return search_by_vector_native(store, vec_index, query_embedding, limit, source)
        end

        search_by_vector_fallback(store, query_embedding, limit, source)
      end

      def search_by_vector_native(store, vec_index, query_embedding, limit, source)
        matches = vec_index.search(query_embedding, k: limit)
        return [] if matches.empty?

        fact_ids = matches.map { |m| m[:fact_id] }
        facts_by_id = batch_find_facts(store, fact_ids)
        receipts_by_fact_id = batch_find_receipts(store, fact_ids)

        Core::ResultBuilder.build_results_with_scores(
          matches,
          facts_by_id: facts_by_id,
          receipts_by_fact_id: receipts_by_fact_id,
          source: source
        )
      end

      def search_by_vector_fallback(store, query_embedding, limit, source)
        facts_data = store.facts_with_embeddings(limit: 5000)
        return [] if facts_data.empty?

        unique_candidates, fact_groups = dedup_candidates(facts_data)
        return [] if unique_candidates.empty?

        top_unique = Embeddings::Similarity.top_k(query_embedding, unique_candidates, limit)
        top_matches = fan_out_matches(top_unique, fact_groups, limit)

        fact_ids = top_matches.map { |m| m[:candidate][:fact_id] }
        facts_by_id = batch_find_facts(store, fact_ids)
        receipts_by_fact_id = batch_find_receipts(store, fact_ids)

        Core::ResultBuilder.build_results_with_scores(
          top_matches,
          facts_by_id: facts_by_id,
          receipts_by_fact_id: receipts_by_fact_id,
          source: source
        )
      end

      def dedup_candidates(facts_data)
        groups = {}
        unique = {}

        facts_data.each do |row|
          key = row[:embedding_json]
          if unique.key?(key)
            groups[key] << row[:id]
          else
            candidate = Core::EmbeddingCandidateBuilder.parse_candidate(row)
            next unless candidate
            unique[key] = candidate
            groups[key] = [row[:id]]
          end
        end

        [unique.values, groups]
      end

      def fan_out_matches(top_unique, fact_groups, limit)
        results = []
        top_unique.each do |match|
          candidate = match[:candidate]
          similarity = match[:similarity]

          group_key = fact_groups.find { |_key, ids| ids.include?(candidate[:fact_id]) }&.first
          next unless group_key

          fact_groups[group_key].each do |fact_id|
            results << {
              candidate: candidate.merge(fact_id: fact_id),
              similarity: similarity
            }
            break if results.size >= limit
          end
          break if results.size >= limit
        end

        results
      end

      # FTS helpers

      def search_by_fts(store, query_text, limit, source)
        fts = Index::LexicalFTS.new(store)
        ranked_results = fts.search_with_ranks(query_text, limit: limit * 2)

        return [] if ranked_results.empty?

        content_ids = ranked_results.map { |r| r[:content_item_id] }

        provenance_rows = store.provenance
          .where(content_item_id: content_ids)
          .select(:fact_id, :content_item_id)
          .all

        content_to_facts = provenance_rows.group_by { |r| r[:content_item_id] }

        ranks = ranked_results.map { |r| r[:rank] }
        min_rank = ranks.min
        max_rank = ranks.max
        range = (max_rank - min_rank).abs

        seen_fact_ids = Set.new
        scored_matches = []

        ranked_results.each do |r|
          similarity = if range > 0
            0.1 + 0.9 * ((max_rank - r[:rank]).abs / range)
          else
            0.8
          end

          fact_ids = content_to_facts[r[:content_item_id]]&.map { |p| p[:fact_id] } || []
          fact_ids.each do |fid|
            next if seen_fact_ids.include?(fid)
            seen_fact_ids.add(fid)
            scored_matches << {fact_id: fid, similarity: similarity}
          end
        end

        return [] if scored_matches.empty?

        fact_ids = scored_matches.map { |m| m[:fact_id] }
        facts_by_id = batch_find_facts(store, fact_ids)
        receipts_by_fact_id = batch_find_receipts(store, fact_ids)

        Core::ResultBuilder.build_results_with_scores(
          scored_matches,
          facts_by_id: facts_by_id,
          receipts_by_fact_id: receipts_by_fact_id,
          source: source
        ).take(limit)
      end

      def merge_search_results(vector_results, text_results, limit)
        Core::FactRanker.merge_search_results(vector_results, text_results, limit)
      end

      def strong_fts_signal?(store, query_text)
        fts = Index::LexicalFTS.new(store)
        ranked_results = fts.search_with_ranks(query_text, limit: 5)
        Recall::ExpansionDetector.strong_fts_signal?(ranked_results)
      end

      # Scope helpers

      def fact_matches_scope?(fact, scope)
        Core::ScopeFilter.matches?(fact, scope, @project_path)
      end

      def apply_scope_filter(dataset, scope)
        Core::ScopeFilter.apply_to_dataset(dataset, scope, @project_path)
      end

      def sort_by_scope_priority(facts_with_provenance)
        Core::FactRanker.sort_by_scope_priority(facts_with_provenance, @project_path)
      end

      # Dedup helpers

      def dedupe_and_sort(results, limit)
        Core::FactRanker.dedupe_and_sort(results, limit)
      end

      def dedupe_and_sort_index(results, limit)
        Core::FactRanker.dedupe_and_sort_index(results, limit)
      end

      def dedupe_by_fact_id(results, limit)
        Core::FactRanker.dedupe_by_fact_id(results, limit)
      end
    end
  end
end
