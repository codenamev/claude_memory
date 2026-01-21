# frozen_string_literal: true

module ClaudeMemory
  class Recall
    SCOPE_PROJECT = "project"
    SCOPE_GLOBAL = "global"
    SCOPE_ALL = "all"

    def initialize(store_or_manager, fts: nil, project_path: nil, env: ENV)
      @project_path = project_path || env["CLAUDE_PROJECT_DIR"] || Dir.pwd

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

    private

    def query_dual(query_text, limit:, scope:)
      results = []

      if scope == SCOPE_ALL || scope == SCOPE_PROJECT
        @manager.ensure_project! if @manager.project_exists?
        if @manager.project_store
          project_results = query_single_store(@manager.project_store, query_text, limit: limit, source: :project)
          results.concat(project_results)
        end
      end

      if scope == SCOPE_ALL || scope == SCOPE_GLOBAL
        @manager.ensure_global! if @manager.global_exists?
        if @manager.global_store
          global_results = query_single_store(@manager.global_store, query_text, limit: limit, source: :global)
          results.concat(global_results)
        end
      end

      dedupe_and_sort(results, limit)
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
        .where(Sequel[:facts][:id] => fact_ids)
        .all
        .each_with_object({}) { |fact, hash| hash[fact[:id]] = fact }
    end

    def batch_find_receipts(store, fact_ids)
      store.provenance
        .left_join(:content_items, id: :content_item_id)
        .select(
          Sequel[:provenance][:id],
          Sequel[:provenance][:fact_id],
          Sequel[:provenance][:quote],
          Sequel[:provenance][:strength],
          Sequel[:content_items][:session_id],
          Sequel[:content_items][:occurred_at]
        )
        .where(Sequel[:provenance][:fact_id] => fact_ids)
        .all
        .group_by { |receipt| receipt[:fact_id] }
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
      results = []

      if scope == SCOPE_ALL || scope == SCOPE_PROJECT
        @manager.ensure_project! if @manager.project_exists?
        if @manager.project_store
          project_changes = fetch_changes(@manager.project_store, since, limit)
          project_changes.each { |c| c[:source] = :project }
          results.concat(project_changes)
        end
      end

      if scope == SCOPE_ALL || scope == SCOPE_GLOBAL
        @manager.ensure_global! if @manager.global_exists?
        if @manager.global_store
          global_changes = fetch_changes(@manager.global_store, since, limit)
          global_changes.each { |c| c[:source] = :global }
          results.concat(global_changes)
        end
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
      results = []

      if scope == SCOPE_ALL || scope == SCOPE_PROJECT
        @manager.ensure_project! if @manager.project_exists?
        if @manager.project_store
          project_conflicts = @manager.project_store.open_conflicts
          project_conflicts.each { |c| c[:source] = :project }
          results.concat(project_conflicts)
        end
      end

      if scope == SCOPE_ALL || scope == SCOPE_GLOBAL
        @manager.ensure_global! if @manager.global_exists?
        if @manager.global_store
          global_conflicts = @manager.global_store.open_conflicts
          global_conflicts.each { |c| c[:source] = :global }
          results.concat(global_conflicts)
        end
      end

      results
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
  end
end
