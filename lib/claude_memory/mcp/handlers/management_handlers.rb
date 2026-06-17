# frozen_string_literal: true

module ClaudeMemory
  module MCP
    module Handlers
      # Management tool handlers (store_extraction, promote, sweep, changes, conflicts)
      module ManagementHandlers
        def store_extraction(args)
          scope = args["scope"] || "project"
          store = get_store_for_scope(scope)
          return {error: "Database not available"} unless store

          entities = (args["entities"] || []).map { |e| symbolize_keys(e) }
          facts = (args["facts"] || []).map { |f| symbolize_keys(f) }
          decisions = (args["decisions"] || []).map { |d| symbolize_keys(d) }

          config = Configuration.new
          project_path = config.project_dir
          occurred_at = Time.now.utc.iso8601

          searchable_text = Core::TextBuilder.build_searchable_text(entities, facts, decisions)
          content_item_id = create_synthetic_content_item(store, searchable_text, project_path, occurred_at)
          index_content_item(store, content_item_id, searchable_text)

          extraction = Distill::Extraction.new(
            entities: entities,
            facts: facts,
            decisions: decisions,
            signals: []
          )

          # Guard against the LLM distiller labeling descriptions of external
          # projects (LOC counts, star counts, "X is a plugin by …") as
          # `convention`. Retag those as `reference` before resolution so
          # they don't pollute the Knowledge-base conventions list or get
          # returned by `memory.conventions`.
          extraction = Distill::ReferenceMaterialDetector.new.reclassify(extraction)

          resolver = Resolve::Resolver.new(store)
          result = resolver.apply(
            extraction,
            content_item_id: content_item_id,
            occurred_at: occurred_at,
            project_path: project_path,
            scope: scope
          )

          {
            success: true,
            scope: scope,
            content_item_id: content_item_id,
            entities_created: result[:entities_created],
            facts_created: result[:facts_created],
            facts_superseded: result[:facts_superseded],
            conflicts_created: result[:conflicts_created]
          }
        end

        # Promotion bridge: turn a corroborated observation into a structured
        # fact. Server-side anti-hallucination gate — refuses to promote an
        # observation that has not been sighted at least PROMOTION_THRESHOLD
        # times. Creates the fact through the resolver (so supersession/conflict
        # handling applies) and marks the observation promoted so it is not
        # re-suggested.
        def promote_observation(args)
          scope = args["scope"] || "project"
          store = get_store_for_scope(scope)
          return {error: "Database not available"} unless store

          observation_id = args["observation_id"]
          return {error: "observation_id required"} if observation_id.nil?

          obs = store.observations.where(id: observation_id).first
          return {error: "Observation #{observation_id} not found in #{scope} database"} unless obs
          return {error: "Observation #{observation_id} already promoted (fact #{obs[:promoted_fact_id]})"} unless obs[:promoted_at].nil?

          threshold = Domain::Observation::PROMOTION_THRESHOLD
          if obs[:corroboration_count].to_i < threshold
            return {error: "Not yet corroborated: observation #{observation_id} has #{obs[:corroboration_count]} sighting(s), need #{threshold}. Promotion requires repeated corroboration (anti-hallucination gate)."}
          end

          predicate = args["predicate"]
          object = args["object"]
          return {error: "predicate and object are required"} if predicate.nil? || object.to_s.strip.empty?
          subject = args["subject"] || "repo"

          config = Configuration.new
          project_path = config.project_dir
          occurred_at = Time.now.utc.iso8601

          extraction = Distill::Extraction.new(
            facts: [{subject: subject, predicate: predicate, object: object, strength: "derived"}]
          )
          result = Resolve::Resolver.new(store).apply(
            extraction, content_item_id: obs[:source_content_item_id],
            occurred_at: occurred_at, project_path: project_path, scope: scope
          )

          fact_id = promoted_fact_id(store, subject, predicate, object)
          store.mark_observation_promoted(observation_id, fact_id: fact_id) if fact_id

          {
            success: true,
            observation_id: observation_id,
            fact_id: fact_id,
            predicate: Resolve::PredicatePolicy.canonicalize(predicate),
            object: object,
            corroboration_count: obs[:corroboration_count],
            facts_created: result[:facts_created]
          }
        end

        def promote(args)
          return {error: "Promote requires StoreManager"} unless @manager

          fact_id = args["fact_id"]
          global_fact_id = @manager.promote_fact(fact_id)

          if global_fact_id
            {
              success: true,
              project_fact_id: fact_id,
              global_fact_id: global_fact_id,
              message: "Fact promoted to global memory"
            }
          else
            {error: "Fact #{fact_id} not found in project database"}
          end
        end

        def reject_fact(args)
          scope = args["scope"] || "project"
          store = get_store_for_scope(scope)
          return {error: "Database not available"} unless store

          fact_id = args["fact_id"]
          if fact_id.nil? && args["docid"]
            row = store.find_fact_by_docid(args["docid"])
            fact_id = row && row[:id]
          end
          return {error: "fact_id or docid required"} if fact_id.nil?

          result = store.reject_fact(fact_id, reason: args["reason"])
          return {error: "Fact #{fact_id} not found in #{scope} database"} if result.nil?

          {
            success: true,
            scope: scope,
            fact_id: fact_id,
            conflicts_resolved: result[:conflicts_resolved],
            message: "Fact rejected"
          }
        end

        def sweep_now(args)
          scope = args["scope"] || "project"
          store = get_store_for_scope(scope)
          return {error: "Database not available"} unless store

          sweeper = Sweep::Sweeper.new(store)
          budget = args["budget_seconds"] || 5
          stats = if args["escalate"]
            sweeper.run_with_escalation!(budget_seconds: budget)
          else
            sweeper.run!(budget_seconds: budget)
          end
          ResponseFormatter.format_sweep_stats(scope, stats)
        end

        def changes(args)
          since = args["since"] || (Time.now - 86400 * 7).utc.iso8601
          scope = args["scope"] || "all"
          list = @recall.changes(since: since, limit: args["limit"] || 20, scope: scope)
          ResponseFormatter.format_changes(since, list)
        end

        def conflicts(args)
          scope = args["scope"] || "all"
          list = @recall.conflicts(scope: scope)
          ResponseFormatter.format_conflicts(list)
        end

        def mark_distilled(args)
          content_item_id = args["content_item_id"]
          facts_extracted = args["facts_extracted"] || 0

          store = find_store_for_content_item(content_item_id)
          return {error: "Content item #{content_item_id} not found"} unless store

          store.record_ingestion_metrics(
            content_item_id: content_item_id,
            input_tokens: 0,
            output_tokens: 0,
            facts_extracted: facts_extracted
          )

          {
            success: true,
            content_item_id: content_item_id,
            facts_extracted: facts_extracted
          }
        end

        private

        def create_synthetic_content_item(store, text, project_path, occurred_at)
          text_hash = Digest::SHA256.hexdigest(text)
          store.upsert_content_item(
            source: "mcp_extraction",
            session_id: "mcp-#{Time.now.to_i}",
            transcript_path: nil,
            project_path: project_path,
            text_hash: text_hash,
            byte_len: text.bytesize,
            raw_text: text,
            occurred_at: occurred_at
          )
        end

        def index_content_item(store, content_item_id, text)
          fts = Index::LexicalFTS.new(store)
          fts.index_content_item(content_item_id, text)
        end

        def symbolize_keys(hash)
          Core::TextBuilder.symbolize_keys(hash)
        end

        # Resolve the fact id the resolver just produced for a promotion, by
        # the canonical (subject, predicate, object) slot — newest row wins.
        def promoted_fact_id(store, subject, predicate, object)
          subject_type = (subject == "user") ? "person" : "repo"
          subject_id = store.find_or_create_entity(type: subject_type, name: subject)
          canonical = Resolve::PredicatePolicy.canonicalize(predicate)
          row = store.facts
            .where(subject_entity_id: subject_id, predicate: canonical, object_literal: object)
            .order(Sequel.desc(:id))
            .first
          row && row[:id]
        end
      end
    end
  end
end
