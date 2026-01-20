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
            description: "Recall facts matching a query",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query"},
                limit: {type: "integer", description: "Max results", default: 10}
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
        else
          {error: "Unknown tool: #{name}"}
        end
      end

      private

      def recall(args)
        results = @recall.query(args["query"], limit: args["limit"] || 10)
        {
          facts: results.map do |r|
            {
              id: r[:fact][:id],
              subject: r[:fact][:subject_name],
              predicate: r[:fact][:predicate],
              object: r[:fact][:object_literal],
              status: r[:fact][:status],
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
        fact_count = @store.execute("SELECT COUNT(*) FROM facts").first.first
        active_count = @store.execute("SELECT COUNT(*) FROM facts WHERE status = 'active'").first.first
        content_count = @store.execute("SELECT COUNT(*) FROM content_items").first.first
        conflict_count = @store.execute("SELECT COUNT(*) FROM conflicts WHERE status = 'open'").first.first

        {
          facts_total: fact_count,
          facts_active: active_count,
          content_items: content_count,
          open_conflicts: conflict_count,
          schema_version: @store.schema_version
        }
      end
    end
  end
end
