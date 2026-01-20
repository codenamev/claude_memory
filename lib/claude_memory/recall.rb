# frozen_string_literal: true

module ClaudeMemory
  class Recall
    SCOPE_PROJECT = "project"
    SCOPE_GLOBAL = "global"
    SCOPE_ALL = "all"

    def initialize(store, fts: nil, project_path: nil, env: ENV)
      @store = store
      @fts = fts || Index::LexicalFTS.new(store)
      @project_path = project_path || env["CLAUDE_PROJECT_DIR"] || Dir.pwd
    end

    def query(query_text, limit: 10, scope: SCOPE_ALL)
      content_ids = @fts.search(query_text, limit: limit * 3)
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

    def explain(fact_id)
      fact = find_fact(fact_id)
      return nil unless fact

      {
        fact: fact,
        receipts: find_receipts(fact_id),
        superseded_by: find_superseded_by(fact_id),
        supersedes: find_supersedes(fact_id),
        conflicts: find_conflicts(fact_id)
      }
    end

    def changes(since:, limit: 50, scope: SCOPE_ALL)
      ds = @store.facts
        .select(:id, :subject_entity_id, :predicate, :object_literal, :status, :created_at, :scope, :project_path)
        .where { created_at >= since }
        .order(Sequel.desc(:created_at))
        .limit(limit)

      ds = apply_scope_filter(ds, scope)
      ds.all
    end

    def conflicts(scope: SCOPE_ALL)
      all_conflicts = @store.open_conflicts
      return all_conflicts if scope == SCOPE_ALL

      all_conflicts.select do |conflict|
        fact_a = find_fact(conflict[:fact_a_id])
        fact_b = find_fact(conflict[:fact_b_id])

        fact_matches_scope?(fact_a, scope) || fact_matches_scope?(fact_b, scope)
      end
    end

    private

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
      @store.provenance
        .select(:id, :fact_id, :content_item_id, :quote, :strength)
        .where(content_item_id: content_id)
        .all
    end

    def find_fact(fact_id)
      @store.facts
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

    def find_receipts(fact_id)
      @store.provenance
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

    def find_superseded_by(fact_id)
      @store.fact_links
        .where(to_fact_id: fact_id, link_type: "supersedes")
        .select_map(:from_fact_id)
    end

    def find_supersedes(fact_id)
      @store.fact_links
        .where(from_fact_id: fact_id, link_type: "supersedes")
        .select_map(:to_fact_id)
    end

    def find_conflicts(fact_id)
      @store.conflicts
        .select(:id, :fact_a_id, :fact_b_id, :status)
        .where(Sequel.or(fact_a_id: fact_id, fact_b_id: fact_id))
        .all
    end
  end
end
