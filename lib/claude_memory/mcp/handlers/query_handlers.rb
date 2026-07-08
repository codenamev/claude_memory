# frozen_string_literal: true

module ClaudeMemory
  module MCP
    module Handlers
      # Query and recall tool handlers
      module QueryHandlers
        def recall(args)
          return database_not_found_error unless databases_exist?

          scope = extract_scope(args)
          limit = extract_limit(args)
          compact = args["compact"] == true
          query = args["query"]
          intent = extract_intent(args)
          results = @recall.query(query, limit: limit, scope: scope, include_raw_text: !compact, intent: intent)
          ResponseFormatter.format_recall_results(results, compact: compact, query: query)
        rescue Sequel::DatabaseError, Sequel::DatabaseConnectionError, Errno::ENOENT => e
          classified_error(e, tool_name: "memory.recall")
        end

        def recall_index(args)
          scope = extract_scope(args)
          limit = extract_limit(args, default: 20)
          intent = extract_intent(args)
          results = @recall.query_index(args["query"], limit: limit, scope: scope, intent: intent)
          ResponseFormatter.format_index_results(args["query"], scope, results)
        end

        def recall_details(args)
          fact_ids = args["fact_ids"]
          scope = args["scope"] || "project"

          explanations = fact_ids.map do |fact_id|
            explanation = @recall.explain(fact_id, scope: scope)
            next nil if explanation.is_a?(Core::NullExplanation)

            ResponseFormatter.format_detailed_explanation(explanation)
          end.compact

          {
            fact_count: explanations.size,
            facts: explanations
          }
        end

        def explain(args)
          scope = args["scope"] || "project"
          explanation = @recall.explain(args["fact_id"], scope: scope)
          return {error: "Fact not found in #{scope} database"} if explanation.is_a?(Core::NullExplanation)

          result = ResponseFormatter.format_explanation(explanation, scope)

          # Episodic provenance: if this fact was promoted from observations,
          # show the lineage back to them (reverse of observations.promoted_fact_id).
          store = get_store_for_scope(scope)
          promoted_from = store ? store.observations_for_fact(args["fact_id"]) : []
          result[:promoted_from_observations] = promoted_from if result.is_a?(Hash) && promoted_from.any?

          result
        end

        def recall_semantic(args)
          query = args["query"]
          mode = (args["mode"] || "both").to_sym
          scope = extract_scope(args)
          limit = extract_limit(args)
          compact = args["compact"] == true
          explain = args["explain"] == true
          intent = extract_intent(args)

          results = @recall.query_semantic(query, limit: limit, scope: scope, mode: mode, explain: explain, intent: intent)
          ResponseFormatter.format_semantic_results(query, mode.to_s, scope, results, compact: compact)
        end

        def search_concepts(args)
          concepts = args["concepts"]
          scope = extract_scope(args)
          limit = extract_limit(args)
          compact = args["compact"] == true

          return {error: "Must provide 2-5 concepts"} unless (2..5).cover?(concepts.size)

          results = @recall.query_concepts(concepts, limit: limit, scope: scope)
          ResponseFormatter.format_concept_results(concepts, scope, results, compact: compact)
        end

        def fact_graph(args)
          fact_id = args["fact_id"]
          depth = args["depth"] || 2
          scope = args["scope"] || "project"

          graph = @recall.fact_graph(fact_id, depth: depth, scope: scope)

          return {error: "Fact #{fact_id} not found in #{scope} database"} if graph[:node_count] == 0

          graph
        end

        def undistilled(args)
          limit = args["limit"] || 3
          min_length = args["min_length"] || 200
          max_text = 2000

          items = collect_undistilled_items(limit: limit, min_length: min_length)

          {
            count: items.size,
            items: items.map { |item|
              {
                content_item_id: item[:id],
                occurred_at: item[:occurred_at],
                occurred_ago: Core::RelativeTime.format(item[:occurred_at]),
                project_path: item[:project_path],
                raw_text: Core::TextBuilder.truncate(item[:raw_text], max_text)
              }
            }
          }
        end

        # List recent episodic observations (the "what happened" log). Read-only.
        # Phase 1 queries one scope's store (default project); cross-scope merge
        # comes with the stable-prefix injection phase.
        def observations(args)
          return database_not_found_error unless databases_exist?

          scope = args["scope"] || "project"
          limit = extract_limit(args, default: 20)
          max_priority = (args["important_only"] == true) ? Domain::Observation::IMPORTANT : nil

          store = get_store_for_scope(scope)
          return {error: "Database not available"} unless store

          rows = store.recent_observations(scope: scope, limit: limit, max_priority: max_priority)

          {
            observation_count: rows.size,
            observations: rows.map { |row|
              obs = Domain::Observation.new(row)
              {
                id: obs.id,
                kind: obs.kind,
                priority: obs.priority,
                body: obs.body,
                scope: obs.scope,
                status: obs.status,
                corroboration_count: obs.corroboration_count,
                promoted_fact_id: obs.promoted_fact_id,
                consolidated_into: obs.consolidated_into,
                source_content_item_id: obs.source_content_item_id,
                observed_at: obs.observed_at,
                observed_ago: Core::RelativeTime.format(obs.observed_at)
              }
            }
          }
        rescue Sequel::DatabaseError, Sequel::DatabaseConnectionError, Errno::ENOENT => e
          classified_error(e, tool_name: "memory.observations")
        end
      end
    end
  end
end
