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
            entities_created: result[:entities_created],
            facts_created: result[:facts_created],
            facts_superseded: result[:facts_superseded],
            conflicts_created: result[:conflicts_created]
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
      end
    end
  end
end
