# frozen_string_literal: true

module ClaudeMemory
  module Resolve
    # Truth maintenance engine that processes distilled extractions into stored facts.
    # Wraps entity resolution, fact insertion, supersession, and conflict detection
    # in a single database transaction.
    #
    # @example
    #   resolver = Resolver.new(store)
    #   result = resolver.apply(extraction, content_item_id: 42, scope: "project")
    #   result[:facts_created]   #=> 3
    #   result[:facts_superseded] #=> 1
    class Resolver
      # @param store [Store::SQLiteStore] backing database for reads and writes
      def initialize(store)
        @store = store
      end

      # Apply a distilled extraction, resolving each fact against existing knowledge.
      # Facts may be inserted, reinforce an existing fact, supersede old facts, or
      # create a conflict when the resolution is ambiguous.
      #
      # @param extraction [#entities, #facts] distilled extraction with entities and facts
      # @param content_item_id [Integer, nil] source content item for provenance
      # @param occurred_at [String, nil] ISO 8601 timestamp (defaults to now)
      # @param project_path [String, nil] project path for scoped facts
      # @param scope [String] default scope for facts ("project" or "global")
      # @return [Hash] counts keyed by :entities_created, :facts_created,
      #   :facts_superseded, :conflicts_created, :provenance_created
      def apply(extraction, content_item_id: nil, occurred_at: nil, project_path: nil, scope: "project")
        occurred_at ||= Time.now.utc.iso8601

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
            outcome = resolve_fact(fact_data, entity_ids, content_item_id, occurred_at,
              project_path: project_path, scope: scope)
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

      def resolve_fact(fact_data, entity_ids, content_item_id, occurred_at, project_path:, scope:)
        # Canonicalize drift-prone predicate synonyms (has_convention →
        # convention, primary_language → uses_language) before anything
        # else looks at the predicate.
        original_predicate = fact_data[:predicate]
        canonical = PredicatePolicy.canonicalize(original_predicate)
        if canonical != original_predicate
          ClaudeMemory.logger.debug("resolve",
            message: "Canonicalized predicate",
            from: original_predicate,
            to: canonical)
          fact_data = fact_data.merge(predicate: canonical)
        end

        log_novel_predicate(canonical) unless PredicatePolicy.known_predicates.include?(canonical)

        subject_id = resolve_subject(fact_data, entity_ids)
        existing_facts = @store.facts_for_slot(subject_id, fact_data[:predicate])
        resolution = determine_resolution(existing_facts, fact_data, entity_ids)

        apply_resolution(resolution, fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts,
          project_path: project_path, scope: scope)
      end

      def log_novel_predicate(predicate)
        ClaudeMemory.logger.warn("resolve",
          message: "Novel predicate encountered",
          predicate: predicate,
          hint: "add to PredicatePolicy::POLICIES or PredicatePolicy::SYNONYMS to canonicalize")
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

      def apply_resolution(resolution, fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts, project_path:, scope:)
        case resolution
        when :reinforce
          apply_reinforcement(existing_facts, fact_data, entity_ids, content_item_id)
        when :conflict
          apply_conflict(existing_facts, fact_data, subject_id, content_item_id, occurred_at,
            project_path: project_path, scope: scope)
        else
          apply_insert(fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts, resolution,
            project_path: project_path, scope: scope)
        end
      end

      def apply_reinforcement(existing_facts, fact_data, entity_ids, content_item_id)
        object_entity_id = entity_ids[fact_data[:object]]
        matching = existing_facts.find { |f| values_match?(f, fact_data[:object], object_entity_id) }
        add_provenance(matching[:id], content_item_id, fact_data)
        {created: 0, superseded: 0, conflicts: 0, provenance: 1}
      end

      def apply_conflict(existing_facts, fact_data, subject_id, content_item_id, occurred_at, project_path:, scope:)
        create_conflict(existing_facts.first[:id], fact_data, subject_id, content_item_id, occurred_at,
          project_path: project_path, scope: scope)
        {created: 0, superseded: 0, conflicts: 1, provenance: 0}
      end

      def apply_insert(fact_data, subject_id, entity_ids, content_item_id, occurred_at, existing_facts, resolution, project_path:, scope:)
        superseded_count = 0
        if resolution == :supersede
          supersede_facts(existing_facts, occurred_at)
          superseded_count = existing_facts.size
        end

        fact_id = insert_new_fact(fact_data, subject_id, entity_ids, occurred_at,
          project_path: project_path, scope: scope)
        link_superseded_facts(fact_id, existing_facts) if superseded_count > 0
        add_provenance(fact_id, content_item_id, fact_data)

        {created: 1, superseded: superseded_count, conflicts: 0, provenance: 1}
      end

      def insert_new_fact(fact_data, subject_id, entity_ids, occurred_at, project_path:, scope:)
        fact_scope = fact_data[:scope_hint] || scope
        fact_project = (fact_scope == "global") ? nil : project_path

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

      def create_conflict(existing_fact_id, new_fact_data, subject_id, content_item_id, occurred_at, project_path:, scope:)
        # Already within transaction from resolve_fact
        new_fact_id = @store.insert_fact(
          subject_entity_id: subject_id,
          predicate: new_fact_data[:predicate],
          object_literal: new_fact_data[:object],
          polarity: new_fact_data[:polarity] || "positive",
          confidence: new_fact_data[:confidence] || 1.0,
          status: "disputed",
          valid_from: occurred_at,
          scope: scope,
          project_path: project_path
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
