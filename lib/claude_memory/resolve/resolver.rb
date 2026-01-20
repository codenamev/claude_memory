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

        entity_ids = resolve_entities(extraction.entities)
        result[:entities_created] = entity_ids.size

        extraction.facts.each do |fact_data|
          outcome = resolve_fact(fact_data, entity_ids, content_item_id, occurred_at)
          result[:facts_created] += outcome[:created]
          result[:facts_superseded] += outcome[:superseded]
          result[:conflicts_created] += outcome[:conflicts]
          result[:provenance_created] += outcome[:provenance]
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
        subject_id = entity_ids[fact_data[:subject]] ||
          @store.find_or_create_entity(type: "repo", name: fact_data[:subject])

        predicate = fact_data[:predicate]
        object_val = fact_data[:object]
        object_entity_id = entity_ids[object_val]

        outcome = {created: 0, superseded: 0, conflicts: 0, provenance: 0}

        existing_facts = @store.facts_for_slot(subject_id, predicate)

        if PredicatePolicy.single?(predicate) && existing_facts.any?
          matching = existing_facts.find { |f| values_match?(f, object_val, object_entity_id) }
          if matching
            add_provenance(matching[:id], content_item_id, fact_data)
            outcome[:provenance] = 1
            return outcome
          elsif supersession_signal?(fact_data)
            supersede_facts(existing_facts, occurred_at)
            outcome[:superseded] = existing_facts.size
          else
            create_conflict(existing_facts.first[:id], fact_data, subject_id, content_item_id, occurred_at)
            outcome[:conflicts] = 1
            return outcome
          end
        end

        fact_id = @store.insert_fact(
          subject_entity_id: subject_id,
          predicate: predicate,
          object_entity_id: object_entity_id,
          object_literal: object_val,
          polarity: fact_data[:polarity] || "positive",
          confidence: fact_data[:confidence] || 1.0,
          valid_from: occurred_at,
          scope: @current_scope,
          project_path: @current_project_path
        )
        outcome[:created] = 1

        if existing_facts.any? && outcome[:superseded] > 0
          existing_facts.each do |old_fact|
            @store.insert_fact_link(from_fact_id: fact_id, to_fact_id: old_fact[:id], link_type: "supersedes")
          end
        end

        add_provenance(fact_id, content_item_id, fact_data)
        outcome[:provenance] = 1

        outcome
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
          strength: fact_data[:strength] || "stated"
        )
      end
    end
  end
end
