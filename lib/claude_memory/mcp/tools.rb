# frozen_string_literal: true

require "json"

module ClaudeMemory
  module MCP
    class Tools
      def initialize(store)
        @store = store
        @recall = Recall.new(store)
      end

      def definitions
        [
          {
            name: "memory.recall",
            description: "Recall facts matching a query. Returns facts with their scope (global or project-specific).",
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
                fact_id: {type: "integer", description: "Fact ID to explain"}
              },
              required: ["fact_id"]
            }
          },
          {
            name: "memory.changes",
            description: "List recent fact changes",
            inputSchema: {
              type: "object",
              properties: {
                since: {type: "string", description: "ISO timestamp"},
                limit: {type: "integer", default: 20}
              }
            }
          },
          {
            name: "memory.conflicts",
            description: "List open conflicts",
            inputSchema: {
              type: "object",
              properties: {}
            }
          },
          {
            name: "memory.sweep_now",
            description: "Run maintenance sweep",
            inputSchema: {
              type: "object",
              properties: {
                budget_seconds: {type: "integer", default: 5}
              }
            }
          },
          {
            name: "memory.status",
            description: "Get memory system status",
            inputSchema: {
              type: "object",
              properties: {}
            }
          },
          {
            name: "memory.set_scope",
            description: "Change a fact's scope to global or project. Use this when the user says a preference should apply everywhere (global) or only to the current project.",
            inputSchema: {
              type: "object",
              properties: {
                fact_id: {type: "integer", description: "Fact ID to update"},
                scope: {type: "string", enum: ["global", "project"], description: "New scope for the fact"},
                project_path: {type: "string", description: "Project path (only needed when setting scope to 'project')"}
              },
              required: ["fact_id", "scope"]
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
          conflicts
        when "memory.sweep_now"
          sweep_now(arguments)
        when "memory.status"
          status
        when "memory.set_scope"
          set_scope(arguments)
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
              scope: r[:fact][:scope] || "project",
              project_path: r[:fact][:project_path],
              receipts: r[:receipts].map { |p| {quote: p[:quote], strength: p[:strength]} }
            }
          end
        }
      end

      def explain(args)
        explanation = @recall.explain(args["fact_id"])
        return {error: "Fact not found"} unless explanation

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
          receipts: explanation[:receipts].map { |p| {quote: p[:quote], strength: p[:strength]} },
          supersedes: explanation[:supersedes],
          superseded_by: explanation[:superseded_by],
          conflicts: explanation[:conflicts].map { |c| c[:id] }
        }
      end

      def changes(args)
        since = args["since"] || (Time.now - 86400 * 7).utc.iso8601
        list = @recall.changes(since: since, limit: args["limit"] || 20)
        {
          since: since,
          changes: list.map do |c|
            {id: c[:id], predicate: c[:predicate], object: c[:object_literal], status: c[:status], created_at: c[:created_at]}
          end
        }
      end

      def conflicts
        list = @store.open_conflicts
        {
          count: list.size,
          conflicts: list.map { |c| {id: c[:id], fact_a: c[:fact_a_id], fact_b: c[:fact_b_id], status: c[:status]} }
        }
      end

      def sweep_now(args)
        sweeper = Sweep::Sweeper.new(@store)
        stats = sweeper.run!(budget_seconds: args["budget_seconds"] || 5)
        {
          proposed_expired: stats[:proposed_facts_expired],
          disputed_expired: stats[:disputed_facts_expired],
          orphaned_deleted: stats[:orphaned_provenance_deleted],
          content_pruned: stats[:old_content_pruned],
          elapsed_seconds: stats[:elapsed_seconds].round(3)
        }
      end

      def status
        {
          facts_total: @store.facts.count,
          facts_active: @store.facts.where(status: "active").count,
          content_items: @store.content_items.count,
          open_conflicts: @store.conflicts.where(status: "open").count,
          schema_version: @store.schema_version
        }
      end

      def set_scope(args)
        fact_id = args["fact_id"]
        scope = args["scope"]
        project_path = args["project_path"]

        return {error: "Invalid scope. Must be 'global' or 'project'"} unless %w[global project].include?(scope)

        explanation = @recall.explain(fact_id)
        return {error: "Fact not found"} unless explanation

        old_scope = explanation[:fact][:scope] || "project"
        old_project = explanation[:fact][:project_path]

        success = @store.update_fact(fact_id, scope: scope, project_path: project_path)

        if success
          {
            fact_id: fact_id,
            old_scope: old_scope,
            new_scope: scope,
            old_project_path: old_project,
            new_project_path: (scope == "global") ? nil : project_path,
            message: (scope == "global") ? "Fact now applies globally across all projects" : "Fact now scoped to project"
          }
        else
          {error: "Failed to update fact scope"}
        end
      end
    end
  end
end
