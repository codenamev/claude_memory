# frozen_string_literal: true

module ClaudeMemory
  module Resolve
    class Resolver
      def initialize(store)
        @store = store
      end

      def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")
        occurred_at ||= Time.now.utc.iso8601
        @current_project_path = project_path
        @current_scope = scope

        result = {
          entities_created: 0,
          facts_created: 0,
          facts_superseded: 0,
          conflicts_created: 0,
          provenance_created: 0
        }

        # Wrap entire extraction in a single transaction for better concurrency
        # This reduces database lock time compared to per-fact transactions
        @store.db.transaction do
          entity_ids = resolve_entities(extraction.entities)
          result[:entities_created] = entity_ids.size

          extraction.facts.each do |fact_data|
            outcome = resolve_fact(fact_data, entity_ids, content_item_id, occurred_at)
            result[:facts_created] += outcome[:created]
            result[:facts_superseded] += outcome[:superseded]
            result[:conflicts_created] += outcome[:conflicts]
            result[:provenance_created] += outcome[:provenance]
          end
        end

        result
      end

      private

      def resolve_entities(entities)
        entity_ids = {}
        entities.uniq { |e| [e[:type], e[:name]] }.each do |e|
          id = @store.find_or_create_entity(type: e[:type], name: e[:name])
          entity_ids[e[:name]] = id
        end
        entity_ids
      end

      def resolve_fact(fact_data, entity_ids, content_item_id, occurred_at)
        subject_id = resolve_subject(fact_data, entity_ids)
        existing_facts = @store.facts_for_slot(subject_id, fact_data[:predicate])
        resolution = determine_resolution(existing_facts, fact_data, entity_ids)

        apply_resolution(resolution, fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts)
      end

      def resolve_subject(fact_data, entity_ids)
        entity_ids[fact_data[:subject]] ||
          @store.find_or_create_entity(type: "repo", name: fact_data[:subject])
      end

      def determine_resolution(existing_facts, fact_data, entity_ids)
        return :insert unless PredicatePolicy.single?(fact_data[:predicate]) && existing_facts.any?

        object_entity_id = entity_ids[fact_data[:object]]
        matching = existing_facts.find { |f| values_match?(f, fact_data[:object], object_entity_id) }

        if matching
          :reinforce
        elsif supersession_signal?(fact_data)
          :supersede
        else
          :conflict
        end
      end

      def apply_resolution(resolution, fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts)
        case resolution
        when :reinforce
          apply_reinforcement(existing_facts, fact_data, entity_ids, content_item_id)
        when :conflict
          apply_conflict(existing_facts, fact_data, subject_id, content_item_id, occurred_at)
        else
          apply_insert(fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts, resolution)
        end
      end

      def apply_reinforcement(existing_facts, fact_data, entity_ids, content_item_id)
        object_entity_id = entity_ids[fact_data[:object]]
        matching = existing_facts.find { |f| values_match?(f, fact_data[:object], object_entity_id) }
        add_provenance(matching[:id], content_item_id, fact_data)
        {created: 0, superseded: 0, conflicts: 0, provenance: 1}
      end

      def apply_conflict(existing_facts, fact_data, subject_id, content_item_id, occurred_at)
        create_conflict(existing_facts.first[:id], fact_data, subject_id, content_item_id, occurred_at)
        {created: 0, superseded: 0, conflicts: 1, provenance: 0}
      end

      def apply_insert(fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts, resolution)
        superseded_count = 0
        if resolution == :supersede
          supersede_facts(existing_facts, occurred_at)
          superseded_count = existing_facts.size
        end

        fact_id = insert_new_fact(fact_data, subject_id, entity_ids, occurred_at)
        link_superseded_facts(fact_id, existing_facts) if superseded_count > 0
        add_provenance(fact_id, content_item_id, fact_data)

        {created: 1, superseded: superseded_count, conflicts: 0, provenance: 1}
      end

      def insert_new_fact(fact_data, subject_id, entity_ids, occurred_at)
        fact_scope = fact_data[:scope_hint] || @current_scope
        fact_project = (fact_scope == "global") ? nil : @current_project_path

        @store.insert_fact(
          subject_entity_id: subject_id,
          predicate: fact_data[:predicate],
          object_entity_id: entity_ids[fact_data[:object]],
          object_literal: fact_data[:object],
          polarity: fact_data[:polarity] || "positive",
          confidence: fact_data[:confidence] || 1.0,
          valid_from: occurred_at,
          scope: fact_scope,
          project_path: fact_project
        )
      end

      def link_superseded_facts(new_fact_id, old_facts)
        old_facts.each do |old_fact|
          @store.insert_fact_link(from_fact_id: new_fact_id, to_fact_id: old_fact[:id], link_type: "supersedes")
        end
      end

      def supersession_signal?(fact_data)
        (fact_data[:strength] == "stated") ||
          fact_data.fetch(:supersedes, false)
      end

      def values_match?(existing_fact, object_val, object_entity_id)
        existing_fact[:object_literal]&.downcase == object_val&.downcase ||
          (object_entity_id && existing_fact[:object_entity_id] == object_entity_id)
      end

      def supersede_facts(facts, occurred_at)
        facts.each do |fact|
          @store.update_fact(fact[:id], status: "superseded", valid_to: occurred_at)
        end
      end

      def create_conflict(existing_fact_id, new_fact_data, subject_id, content_item_id, occurred_at)
        # Already within transaction from resolve_fact
        new_fact_id = @store.insert_fact(
          subject_entity_id: subject_id,
          predicate: new_fact_data[:predicate],
          object_literal: new_fact_data[:object],
          polarity: new_fact_data[:polarity] || "positive",
          confidence: new_fact_data[:confidence] || 1.0,
          status: "disputed",
          valid_from: occurred_at,
          scope: @current_scope,
          project_path: @current_project_path
        )

        @store.insert_conflict(
          fact_a_id: existing_fact_id,
          fact_b_id: new_fact_id,
          notes: "Contradicting #{new_fact_data[:predicate]} claims"
        )

        add_provenance(new_fact_id, content_item_id, new_fact_data)
      end

      def add_provenance(fact_id, content_item_id, fact_data)
        @store.insert_provenance(
          fact_id: fact_id,
          content_item_id: content_item_id,
          quote: fact_data[:quote],
          strength: fact_data[:strength] || "stated",
          line_start: fact_data[:line_start],
          line_end: fact_data[:line_end]
        )
      end
    end
  end
end
