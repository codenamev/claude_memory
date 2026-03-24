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

          ResponseFormatter.format_explanation(explanation, scope)
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

          items = collect_undistilled(limit, min_length)

          {
            count: items.size,
            items: items.map { |item|
              raw = item[:raw_text] || ""
              {
                content_item_id: item[:id],
                occurred_at: item[:occurred_at],
                occurred_ago: Core::RelativeTime.format(item[:occurred_at]),
                project_path: item[:project_path],
                raw_text: (raw.length > max_text) ? raw[0, max_text] + "..." : raw
              }
            }
          }
        end

        private

        def collect_undistilled(limit, min_length)
          if @manager
            project_items = @manager.project_store&.undistilled_content_items(limit: limit, min_length: min_length) || []
            global_items = @manager.global_store&.undistilled_content_items(limit: limit, min_length: min_length) || []
            (project_items + global_items)
              .sort_by { |i| i[:occurred_at] || "" }
              .reverse
              .first(limit)
          elsif @legacy_store
            @legacy_store.undistilled_content_items(limit: limit, min_length: min_length)
          else
            []
          end
        end
      end
    end
  end
end
