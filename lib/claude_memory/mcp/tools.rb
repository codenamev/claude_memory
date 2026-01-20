# frozen_string_literal: true

require "json"

module ClaudeMemory
  module MCP
    class Tools
      def initialize(store_or_manager)
        @recall = Recall.new(store_or_manager)

        if store_or_manager.is_a?(Store::StoreManager)
          @manager = store_or_manager
        else
          @legacy_store = store_or_manager
        end
      end

      def definitions
        [
          {
            name: "memory.recall",
            description: "Recall facts matching a query. Searches both global and project databases.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query"},
                limit: {type: "integer", description: "Max results", default: 10},
                scope: {type: "string", enum: ["all", "global", "project"], description: "Filter by scope: 'all' (default), 'global', or 'project'", default: "all"}
              },
              required: ["query"]
            }
          },
          {
            name: "memory.explain",
            description: "Get detailed explanation of a fact with provenance",
            inputSchema: {
              type: "object",
              properties: {
                fact_id: {type: "integer", description: "Fact ID to explain"},
                scope: {type: "string", enum: ["global", "project"], description: "Which database to look in", default: "project"}
              },
              required: ["fact_id"]
            }
          },
          {
            name: "memory.changes",
            description: "List recent fact changes from both databases",
            inputSchema: {
              type: "object",
              properties: {
                since: {type: "string", description: "ISO timestamp"},
                limit: {type: "integer", default: 20},
                scope: {type: "string", enum: ["all", "global", "project"], default: "all"}
              }
            }
          },
          {
            name: "memory.conflicts",
            description: "List open conflicts from both databases",
            inputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: ["all", "global", "project"], default: "all"}
              }
            }
          },
          {
            name: "memory.sweep_now",
            description: "Run maintenance sweep on a database",
            inputSchema: {
              type: "object",
              properties: {
                budget_seconds: {type: "integer", default: 5},
                scope: {type: "string", enum: ["global", "project"], default: "project"}
              }
            }
          },
          {
            name: "memory.status",
            description: "Get memory system status for both databases",
            inputSchema: {
              type: "object",
              properties: {}
            }
          },
          {
            name: "memory.promote",
            description: "Promote a project fact to global memory. Use when user says a preference should apply everywhere.",
            inputSchema: {
              type: "object",
              properties: {
                fact_id: {type: "integer", description: "Project fact ID to promote to global"}
              },
              required: ["fact_id"]
            }
          }
        ]
      end

      def call(name, arguments)
        case name
        when "memory.recall"
          recall(arguments)
        when "memory.explain"
          explain(arguments)
        when "memory.changes"
          changes(arguments)
        when "memory.conflicts"
          conflicts(arguments)
        when "memory.sweep_now"
          sweep_now(arguments)
        when "memory.status"
          status
        when "memory.promote"
          promote(arguments)
        else
          {error: "Unknown tool: #{name}"}
        end
      end

      private

      def recall(args)
        scope = args["scope"] || "all"
        results = @recall.query(args["query"], limit: args["limit"] || 10, scope: scope)
        {
          facts: results.map do |r|
            {
              id: r[:fact][:id],
              subject: r[:fact][:subject_name],
              predicate: r[:fact][:predicate],
              object: r[:fact][:object_literal],
              status: r[:fact][:status],
              source: r[:source],
              receipts: r[:receipts].map { |p| {quote: p[:quote], strength: p[:strength]} }
            }
          end
        }
      end

      def explain(args)
        scope = args["scope"] || "project"
        explanation = @recall.explain(args["fact_id"], scope: scope)
        return {error: "Fact not found in #{scope} database"} unless explanation

        {
          fact: {
            id: explanation[:fact][:id],
            subject: explanation[:fact][:subject_name],
            predicate: explanation[:fact][:predicate],
            object: explanation[:fact][:object_literal],
            status: explanation[:fact][:status],
            valid_from: explanation[:fact][:valid_from],
            valid_to: explanation[:fact][:valid_to]
          },
          source: scope,
          receipts: explanation[:receipts].map { |p| {quote: p[:quote], strength: p[:strength]} },
          supersedes: explanation[:supersedes],
          superseded_by: explanation[:superseded_by],
          conflicts: explanation[:conflicts].map { |c| c[:id] }
        }
      end

      def changes(args)
        since = args["since"] || (Time.now - 86400 * 7).utc.iso8601
        scope = args["scope"] || "all"
        list = @recall.changes(since: since, limit: args["limit"] || 20, scope: scope)
        {
          since: since,
          changes: list.map do |c|
            {
              id: c[:id],
              predicate: c[:predicate],
              object: c[:object_literal],
              status: c[:status],
              created_at: c[:created_at],
              source: c[:source]
            }
          end
        }
      end

      def conflicts(args)
        scope = args["scope"] || "all"
        list = @recall.conflicts(scope: scope)
        {
          count: list.size,
          conflicts: list.map do |c|
            {
              id: c[:id],
              fact_a: c[:fact_a_id],
              fact_b: c[:fact_b_id],
              status: c[:status],
              source: c[:source]
            }
          end
        }
      end

      def sweep_now(args)
        scope = args["scope"] || "project"
        store = get_store_for_scope(scope)
        return {error: "Database not available"} unless store

        sweeper = Sweep::Sweeper.new(store)
        stats = sweeper.run!(budget_seconds: args["budget_seconds"] || 5)
        {
          scope: scope,
          proposed_expired: stats[:proposed_facts_expired],
          disputed_expired: stats[:disputed_facts_expired],
          orphaned_deleted: stats[:orphaned_provenance_deleted],
          content_pruned: stats[:old_content_pruned],
          elapsed_seconds: stats[:elapsed_seconds].round(3)
        }
      end

      def status
        result = {databases: {}}

        if @manager
          if @manager.global_exists?
            @manager.ensure_global!
            result[:databases][:global] = db_stats(@manager.global_store)
          else
            result[:databases][:global] = {exists: false}
          end

          if @manager.project_exists?
            @manager.ensure_project!
            result[:databases][:project] = db_stats(@manager.project_store)
          else
            result[:databases][:project] = {exists: false}
          end
        else
          result[:databases][:legacy] = db_stats(@legacy_store)
        end

        result
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

      def get_store_for_scope(scope)
        if @manager
          @manager.store_for_scope(scope)
        else
          @legacy_store
        end
      end

      def db_stats(store)
        {
          exists: true,
          facts_total: store.facts.count,
          facts_active: store.facts.where(status: "active").count,
          content_items: store.content_items.count,
          open_conflicts: store.conflicts.where(status: "open").count,
          schema_version: store.schema_version
        }
      end
    end
  end
end
