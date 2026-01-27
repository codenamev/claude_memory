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
      @project_path = project_path || config.project_dir
      @embedding_generator = embedding_generator || Embeddings::Generator.new

      if store_or_manager.is_a?(Store::StoreManager)
        @manager = store_or_manager
        @legacy_mode = false
      else
        @legacy_store = store_or_manager
        @legacy_fts = fts || Index::LexicalFTS.new(store_or_manager)
        @legacy_mode = true
      end
    end

    def query(query_text, limit: 10, scope: SCOPE_ALL)
      if @legacy_mode
        query_legacy(query_text, limit: limit, scope: scope)
      else
        query_dual(query_text, limit: limit, scope: scope)
      end
    end

    def query_index(query_text, limit: 20, scope: SCOPE_ALL)
      if @legacy_mode
        query_index_legacy(query_text, limit: limit, scope: scope)
      else
        query_index_dual(query_text, limit: limit, scope: scope)
      end
    end

    def explain(fact_id, scope: nil)
      if @legacy_mode
        explain_from_store(@legacy_store, fact_id)
      else
        scope ||= SCOPE_PROJECT
        store = @manager.store_for_scope(scope)
        explain_from_store(store, fact_id)
      end
    end

    def changes(since:, limit: 50, scope: SCOPE_ALL)
      if @legacy_mode
        changes_legacy(since: since, limit: limit, scope: scope)
      else
        changes_dual(since: since, limit: limit, scope: scope)
      end
    end

    def conflicts(scope: SCOPE_ALL)
      if @legacy_mode
        conflicts_legacy(scope: scope)
      else
        conflicts_dual(scope: scope)
      end
    end

    def facts_by_branch(branch_name, limit: 20, scope: SCOPE_ALL)
      if @legacy_mode
        facts_by_context_legacy(:git_branch, branch_name, limit: limit, scope: scope)
      else
        facts_by_context_dual(:git_branch, branch_name, limit: limit, scope: scope)
      end
    end

    def facts_by_directory(cwd, limit: 20, scope: SCOPE_ALL)
      if @legacy_mode
        facts_by_context_legacy(:cwd, cwd, limit: limit, scope: scope)
      else
        facts_by_context_dual(:cwd, cwd, limit: limit, scope: scope)
      end
    end

    def facts_by_tool(tool_name, limit: 20, scope: SCOPE_ALL)
      if @legacy_mode
        facts_by_tool_legacy(tool_name, limit: limit, scope: scope)
      else
        facts_by_tool_dual(tool_name, limit: limit, scope: scope)
      end
    end

    def query_semantic(text, limit: 10, scope: SCOPE_ALL, mode: :both)
      if @legacy_mode
        query_semantic_legacy(text, limit: limit, scope: scope, mode: mode)
      else
        query_semantic_dual(text, limit: limit, scope: scope, mode: mode)
      end
    end

    def query_concepts(concepts, limit: 10, scope: SCOPE_ALL)
      raise ArgumentError, "Must provide 2-5 concepts" unless (2..5).cover?(concepts.size)

      if @legacy_mode
        query_concepts_legacy(concepts, limit: limit, scope: scope)
      else
        query_concepts_dual(concepts, limit: limit, scope: scope)
      end
    end

    private

    def query_dual(query_text, limit:, scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        query_single_store(store, query_text, limit: limit, source: source)
      end
      dedupe_and_sort(results, limit)
    end

    def query_index_dual(query_text, limit:, scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        query_index_single_store(store, query_text, limit: limit, source: source)
      end
      dedupe_and_sort_index(results, limit)
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

    def dedupe_and_sort_index(results, limit)
      seen_signatures = Set.new
      unique_results = []

      results.each do |result|
        sig = "#{result[:subject]}:#{result[:predicate]}:#{result[:object_preview]}"
        next if seen_signatures.include?(sig)

        seen_signatures.add(sig)
        unique_results << result
      end

      # Sort by source priority (project first)
      unique_results.sort_by do |item|
        source_priority = (item[:source] == :project) ? 0 : 1
        [source_priority]
      end.first(limit)
    end

    def query_single_store(store, query_text, limit:, source:)
      fts = Index::LexicalFTS.new(store)
      content_ids = fts.search(query_text, limit: limit * 3)
      return [] if content_ids.empty?

      # Collect all fact_ids first
      seen_fact_ids = Set.new
      ordered_fact_ids = []

      content_ids.each do |content_id|
        provenance_records = store.provenance
          .select(:fact_id)
          .where(content_item_id: content_id)
          .all

        provenance_records.each do |prov|
          fact_id = prov[:fact_id]
          next if seen_fact_ids.include?(fact_id)

          seen_fact_ids.add(fact_id)
          ordered_fact_ids << fact_id
          break if ordered_fact_ids.size >= limit
        end
        break if ordered_fact_ids.size >= limit
      end

      return [] if ordered_fact_ids.empty?

      # Batch query all facts at once
      facts_by_id = batch_find_facts(store, ordered_fact_ids)

      # Batch query all receipts at once
      receipts_by_fact_id = batch_find_receipts(store, ordered_fact_ids)

      # Build results maintaining order
      ordered_fact_ids.map do |fact_id|
        fact = facts_by_id[fact_id]
        next unless fact

        {
          fact: fact,
          receipts: receipts_by_fact_id[fact_id] || [],
          source: source
        }
      end.compact
    end

    def batch_find_facts(store, fact_ids)
      dataset = store.facts
        .left_join(:entities, id: :subject_entity_id)
        .select(
          Sequel[:facts][:id],
          Sequel[:facts][:predicate],
          Sequel[:facts][:object_literal],
          Sequel[:facts][:status],
          Sequel[:facts][:confidence],
          Sequel[:facts][:valid_from],
          Sequel[:facts][:valid_to],
          Sequel[:facts][:created_at],
          Sequel[:entities][:canonical_name].as(:subject_name),
          Sequel[:facts][:scope],
          Sequel[:facts][:project_path]
        )

      Core::BatchLoader.load_many(dataset, fact_ids, group_by: :single)
    end

    def batch_find_receipts(store, fact_ids)
      dataset = store.provenance
        .left_join(:content_items, id: :content_item_id)
        .select(
          Sequel[:provenance][:id],
          Sequel[:provenance][:fact_id],
          Sequel[:provenance][:quote],
          Sequel[:provenance][:strength],
          Sequel[:content_items][:session_id],
          Sequel[:content_items][:occurred_at]
        )

      Core::BatchLoader.load_many(dataset, fact_ids, group_by: :fact_id)
    end

    def dedupe_and_sort(results, limit)
      seen_signatures = Set.new
      unique_results = []

      results.each do |result|
        fact = result[:fact]
        sig = "#{fact[:subject_name]}:#{fact[:predicate]}:#{fact[:object_literal]}"
        next if seen_signatures.include?(sig)

        seen_signatures.add(sig)
        unique_results << result
      end

      unique_results.sort_by do |item|
        source_priority = (item[:source] == :project) ? 0 : 1
        [source_priority, item[:fact][:created_at]]
      end.first(limit)
    end

    def changes_dual(since:, limit:, scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        changes = fetch_changes(store, since, limit)
        changes.each { |c| c[:source] = source }
        changes
      end
      results.sort_by { |c| c[:created_at] }.reverse.first(limit)
    end

    def fetch_changes(store, since, limit)
      store.facts
        .select(:id, :subject_entity_id, :predicate, :object_literal, :status, :created_at, :scope, :project_path)
        .where { created_at >= since }
        .order(Sequel.desc(:created_at))
        .limit(limit)
        .all
    end

    def conflicts_dual(scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      template.execute(scope: scope) do |store, source|
        conflicts = store.open_conflicts
        conflicts.each { |c| c[:source] = source }
        conflicts
      end
    end

    def explain_from_store(store, fact_id)
      fact = find_fact_from_store(store, fact_id)
      return Core::NullExplanation.new unless fact

      {
        fact: fact,
        receipts: find_receipts_from_store(store, fact_id),
        superseded_by: find_superseded_by_from_store(store, fact_id),
        supersedes: find_supersedes_from_store(store, fact_id),
        conflicts: find_conflicts_from_store(store, fact_id)
      }
    end

    def find_fact_from_store(store, fact_id)
      store.facts
        .left_join(:entities, id: :subject_entity_id)
        .select(
          Sequel[:facts][:id],
          Sequel[:facts][:predicate],
          Sequel[:facts][:object_literal],
          Sequel[:facts][:status],
          Sequel[:facts][:confidence],
          Sequel[:facts][:valid_from],
          Sequel[:facts][:valid_to],
          Sequel[:facts][:created_at],
          Sequel[:entities][:canonical_name].as(:subject_name),
          Sequel[:facts][:scope],
          Sequel[:facts][:project_path]
        )
        .where(Sequel[:facts][:id] => fact_id)
        .first
    end

    def find_receipts_from_store(store, fact_id)
      store.provenance
        .left_join(:content_items, id: :content_item_id)
        .select(
          Sequel[:provenance][:id],
          Sequel[:provenance][:quote],
          Sequel[:provenance][:strength],
          Sequel[:content_items][:session_id],
          Sequel[:content_items][:occurred_at]
        )
        .where(Sequel[:provenance][:fact_id] => fact_id)
        .all
    end

    def find_superseded_by_from_store(store, fact_id)
      store.fact_links
        .where(to_fact_id: fact_id, link_type: "supersedes")
        .select_map(:from_fact_id)
    end

    def find_supersedes_from_store(store, fact_id)
      store.fact_links
        .where(from_fact_id: fact_id, link_type: "supersedes")
        .select_map(:to_fact_id)
    end

    def find_conflicts_from_store(store, fact_id)
      store.conflicts
        .select(:id, :fact_a_id, :fact_b_id, :status)
        .where(Sequel.or(fact_a_id: fact_id, fact_b_id: fact_id))
        .all
    end

    def query_legacy(query_text, limit:, scope:)
      content_ids = @legacy_fts.search(query_text, limit: limit * 3)
      return [] if content_ids.empty?

      facts_with_provenance = []
      seen_fact_ids = Set.new

      content_ids.each do |content_id|
        provenance_records = find_provenance_by_content(content_id)
        provenance_records.each do |prov|
          next if seen_fact_ids.include?(prov[:fact_id])

          fact = find_fact(prov[:fact_id])
          next unless fact
          next unless fact_matches_scope?(fact, scope)

          seen_fact_ids.add(prov[:fact_id])
          facts_with_provenance << {
            fact: fact,
            receipts: find_receipts(prov[:fact_id])
          }
          break if facts_with_provenance.size >= limit
        end
        break if facts_with_provenance.size >= limit
      end

      sort_by_scope_priority(facts_with_provenance)
    end

    def query_index_legacy(query_text, limit:, scope:)
      options = Index::QueryOptions.new(
        query_text: query_text,
        limit: limit,
        scope: :all,
        source: :legacy
      )

      query = Index::IndexQuery.new(@legacy_store, options)
      results = query.execute

      # Filter by scope in legacy mode
      results.select do |result|
        # Need to get full fact to check scope
        fact = find_fact(result[:id])
        fact && fact_matches_scope?(fact, scope)
      end
    end

    def changes_legacy(since:, limit:, scope:)
      ds = @legacy_store.facts
        .select(:id, :subject_entity_id, :predicate, :object_literal, :status, :created_at, :scope, :project_path)
        .where { created_at >= since }
        .order(Sequel.desc(:created_at))
        .limit(limit)

      ds = apply_scope_filter(ds, scope)
      ds.all
    end

    def conflicts_legacy(scope:)
      all_conflicts = @legacy_store.open_conflicts
      return all_conflicts if scope == SCOPE_ALL

      all_conflicts.select do |conflict|
        fact_a = find_fact(conflict[:fact_a_id])
        fact_b = find_fact(conflict[:fact_b_id])

        fact_matches_scope?(fact_a, scope) || fact_matches_scope?(fact_b, scope)
      end
    end

    def fact_matches_scope?(fact, scope)
      return true if scope == SCOPE_ALL

      fact_scope = fact[:scope] || "project"
      fact_project = fact[:project_path]

      case scope
      when SCOPE_PROJECT
        fact_scope == "project" && fact_project == @project_path
      when SCOPE_GLOBAL
        fact_scope == "global"
      else
        true
      end
    end

    def apply_scope_filter(dataset, scope)
      case scope
      when SCOPE_PROJECT
        dataset.where(scope: "project", project_path: @project_path)
      when SCOPE_GLOBAL
        dataset.where(scope: "global")
      else
        dataset
      end
    end

    def sort_by_scope_priority(facts_with_provenance)
      facts_with_provenance.sort_by do |item|
        fact = item[:fact]
        is_current_project = fact[:project_path] == @project_path
        is_global = fact[:scope] == "global"

        [is_current_project ? 0 : 1, is_global ? 0 : 1]
      end
    end

    def find_provenance_by_content(content_id)
      @legacy_store.provenance
        .select(:id, :fact_id, :content_item_id, :quote, :strength)
        .where(content_item_id: content_id)
        .all
    end

    def find_fact(fact_id)
      find_fact_from_store(@legacy_store, fact_id)
    end

    def find_receipts(fact_id)
      find_receipts_from_store(@legacy_store, fact_id)
    end

    # Context-aware query helpers

    def facts_by_context_dual(column, value, limit:, scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        facts_by_context_single(store, column, value, limit: limit, source: source)
      end
      dedupe_and_sort(results, limit)
    end

    def facts_by_context_legacy(column, value, limit:, scope:)
      facts_by_context_single(@legacy_store, column, value, limit: limit, source: :legacy)
    end

    def facts_by_context_single(store, column, value, limit:, source:)
      # Find content items matching the context
      content_ids = store.content_items
        .where(column => value)
        .select(:id)
        .map { |row| row[:id] }

      return [] if content_ids.empty?

      # Find facts linked to those content items via provenance
      fact_ids = store.provenance
        .where(content_item_id: content_ids)
        .select(:fact_id)
        .distinct
        .map { |row| row[:fact_id] }

      return [] if fact_ids.empty?

      # Batch fetch facts and their provenance
      facts_by_id = batch_find_facts(store, fact_ids)
      receipts_by_fact_id = batch_find_receipts(store, fact_ids)

      fact_ids.map do |fact_id|
        fact = facts_by_id[fact_id]
        next unless fact

        {
          fact: fact,
          receipts: receipts_by_fact_id[fact_id] || [],
          source: source
        }
      end.compact.take(limit)
    end

    def facts_by_tool_dual(tool_name, limit:, scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        facts_by_tool_single(store, tool_name, limit: limit, source: source)
      end
      dedupe_and_sort(results, limit)
    end

    def facts_by_tool_legacy(tool_name, limit:, scope:)
      facts_by_tool_single(@legacy_store, tool_name, limit: limit, source: :legacy)
    end

    def facts_by_tool_single(store, tool_name, limit:, source:)
      # Find content items where the tool was used
      content_ids = store.tool_calls
        .where(tool_name: tool_name)
        .select(:content_item_id)
        .distinct
        .map { |row| row[:content_item_id] }

      return [] if content_ids.empty?

      # Find facts linked to those content items via provenance
      fact_ids = store.provenance
        .where(content_item_id: content_ids)
        .select(:fact_id)
        .distinct
        .map { |row| row[:fact_id] }

      return [] if fact_ids.empty?

      # Batch fetch facts and their provenance
      facts_by_id = batch_find_facts(store, fact_ids)
      receipts_by_fact_id = batch_find_receipts(store, fact_ids)

      fact_ids.map do |fact_id|
        fact = facts_by_id[fact_id]
        next unless fact

        {
          fact: fact,
          receipts: receipts_by_fact_id[fact_id] || [],
          source: source
        }
      end.compact.take(limit)
    end

    # Semantic search helpers

    def query_semantic_dual(text, limit:, scope:, mode:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        query_semantic_single(store, text, limit: limit * 3, mode: mode, source: source)
      end
      dedupe_and_sort(results, limit)
    end

    def query_semantic_legacy(text, limit:, scope:, mode:)
      query_semantic_single(@legacy_store, text, limit: limit, mode: mode, source: :legacy)
    end

    def query_semantic_single(store, text, limit:, mode:, source:)
      vector_results = []
      text_results = []

      # Vector search mode
      if mode == :vector || mode == :both
        vector_results = search_by_vector(store, text, limit, source)
      end

      # Text search mode (FTS)
      if mode == :text || mode == :both
        text_results = search_by_fts(store, text, limit, source)
      end

      # Merge and deduplicate
      merge_search_results(vector_results, text_results, limit)
    end

    def search_by_vector(store, query_text, limit, source)
      # Generate query embedding
      query_embedding = @embedding_generator.generate(query_text)

      # Load facts with embeddings
      facts_data = store.facts_with_embeddings(limit: 5000)
      return [] if facts_data.empty?

      # Parse embeddings and prepare candidates
      candidates = facts_data.map do |row|
        embedding = JSON.parse(row[:embedding_json])
        {
          fact_id: row[:id],
          embedding: embedding,
          subject_entity_id: row[:subject_entity_id],
          predicate: row[:predicate],
          object_literal: row[:object_literal],
          scope: row[:scope]
        }
      rescue JSON::ParserError
        nil
      end.compact

      return [] if candidates.empty?

      # Calculate similarities and rank
      top_matches = Embeddings::Similarity.top_k(query_embedding, candidates, limit)

      # Batch fetch full fact details
      fact_ids = top_matches.map { |m| m[:candidate][:fact_id] }
      facts_by_id = batch_find_facts(store, fact_ids)
      receipts_by_fact_id = batch_find_receipts(store, fact_ids)

      # Build results with similarity scores
      top_matches.map do |match|
        fact_id = match[:candidate][:fact_id]
        fact = facts_by_id[fact_id]
        next unless fact

        {
          fact: fact,
          receipts: receipts_by_fact_id[fact_id] || [],
          source: source,
          similarity: match[:similarity]
        }
      end.compact
    end

    def search_by_fts(store, query_text, limit, source)
      # Use existing FTS search infrastructure
      fts = Index::LexicalFTS.new(store)
      content_ids = fts.search(query_text, limit: limit * 2)

      return [] if content_ids.empty?

      # Find facts from content items
      fact_ids = store.provenance
        .where(content_item_id: content_ids)
        .select(:fact_id)
        .distinct
        .map { |row| row[:fact_id] }

      return [] if fact_ids.empty?

      # Batch fetch facts
      facts_by_id = batch_find_facts(store, fact_ids)
      receipts_by_fact_id = batch_find_receipts(store, fact_ids)

      fact_ids.map do |fact_id|
        fact = facts_by_id[fact_id]
        next unless fact

        {
          fact: fact,
          receipts: receipts_by_fact_id[fact_id] || [],
          source: source,
          similarity: 0.5  # Default score for FTS results
        }
      end.compact.take(limit)
    end

    def merge_search_results(vector_results, text_results, limit)
      # Combine results, preferring vector similarity scores
      combined = {}

      vector_results.each do |result|
        fact_id = result[:fact][:id]
        combined[fact_id] = result
      end

      text_results.each do |result|
        fact_id = result[:fact][:id]
        # Only add if not already present from vector search
        combined[fact_id] ||= result
      end

      # Sort by similarity score (highest first)
      combined.values
        .sort_by { |r| -(r[:similarity] || 0) }
        .take(limit)
    end

    # Multi-concept search helpers

    def query_concepts_dual(concepts, limit:, scope:)
      template = Recall::DualQueryTemplate.new(@manager)
      results = template.execute(scope: scope, limit: limit) do |store, source|
        query_concepts_single(store, concepts, limit: limit * 2, source: source)
      end
      # Deduplicate and sort by average similarity
      dedupe_by_fact_id(results, limit)
    end

    def query_concepts_legacy(concepts, limit:, scope:)
      query_concepts_single(@legacy_store, concepts, limit: limit, source: :legacy)
    end

    def query_concepts_single(store, concepts, limit:, source:)
      # Search each concept independently with higher limit for intersection
      concept_results = concepts.map do |concept|
        search_by_vector(store, concept, limit * 5, source)
      end

      # Build map: fact_id => [results per concept]
      fact_map = Hash.new { |h, k| h[k] = [] }

      concept_results.each_with_index do |results, concept_idx|
        results.each do |result|
          fact_id = result[:fact][:id]
          fact_map[fact_id] << {
            result: result,
            concept_idx: concept_idx,
            similarity: result[:similarity] || 0.0
          }
        end
      end

      # Filter to facts matching ALL concepts
      multi_concept_facts = fact_map.select do |_fact_id, matches|
        represented_concepts = matches.map { |m| m[:concept_idx] }.uniq
        represented_concepts.size == concepts.size
      end

      return [] if multi_concept_facts.empty?

      # Rank by average similarity across all concepts
      ranked = multi_concept_facts.map do |fact_id, matches|
        similarities = matches.map { |m| m[:similarity] }
        avg_similarity = similarities.sum / similarities.size.to_f

        # Use the first match for fact and receipts data
        first_match = matches.first[:result]

        {
          fact: first_match[:fact],
          receipts: first_match[:receipts],
          source: source,
          similarity: avg_similarity,
          concept_similarities: similarities
        }
      end

      # Sort by average similarity (highest first)
      ranked.sort_by { |r| -r[:similarity] }.take(limit)
    end

    def dedupe_by_fact_id(results, limit)
      seen = {}

      results.each do |result|
        fact_id = result[:fact][:id]
        # Keep the result with highest similarity for each fact
        if !seen[fact_id] || seen[fact_id][:similarity] < result[:similarity]
          seen[fact_id] = result
        end
      end

      seen.values.sort_by { |r| -r[:similarity] }.take(limit)
    end
  end
end
