# frozen_string_literal: true

require "json"
require "digest"

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
            name: "memory.recall_index",
            description: "Layer 1: Search for facts and get lightweight index (IDs, previews, token counts). Use this first before fetching full details.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query for fact discovery"},
                limit: {type: "integer", description: "Maximum results to return", default: 20},
                scope: {type: "string", enum: ["all", "global", "project"], description: "Scope: 'all' (both), 'global' (user-wide), 'project' (current only)", default: "all"}
              },
              required: ["query"]
            }
          },
          {
            name: "memory.recall_details",
            description: "Layer 2: Fetch full details for specific fact IDs from the index. Use after memory.recall_index to get complete information.",
            inputSchema: {
              type: "object",
              properties: {
                fact_ids: {type: "array", items: {type: "integer"}, description: "Fact IDs from memory.recall_index"},
                scope: {type: "string", enum: ["project", "global"], description: "Database to query", default: "project"}
              },
              required: ["fact_ids"]
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
          },
          {
            name: "memory.store_extraction",
            description: "Store extracted facts, entities, and decisions from a conversation. Call this to persist knowledge you've learned during the session.",
            inputSchema: {
              type: "object",
              properties: {
                entities: {
                  type: "array",
                  description: "Entities mentioned (databases, frameworks, services, etc.)",
                  items: {
                    type: "object",
                    properties: {
                      type: {type: "string", description: "Entity type: database, framework, language, platform, repo, module, person, service"},
                      name: {type: "string", description: "Canonical name"},
                      confidence: {type: "number", description: "0.0-1.0 extraction confidence"}
                    },
                    required: ["type", "name"]
                  }
                },
                facts: {
                  type: "array",
                  description: "Facts learned during the session",
                  items: {
                    type: "object",
                    properties: {
                      subject: {type: "string", description: "Entity name or 'repo' for project-level facts"},
                      predicate: {type: "string", description: "Relationship type: uses_database, uses_framework, convention, decision, auth_method, deployment_platform"},
                      object: {type: "string", description: "The value or target entity"},
                      confidence: {type: "number", description: "0.0-1.0 how confident"},
                      quote: {type: "string", description: "Source text excerpt (max 200 chars)"},
                      strength: {type: "string", enum: ["stated", "inferred"], description: "Was this explicitly stated or inferred?"},
                      scope_hint: {type: "string", enum: ["project", "global"], description: "Should this apply to just this project or globally?"}
                    },
                    required: ["subject", "predicate", "object"]
                  }
                },
                decisions: {
                  type: "array",
                  description: "Decisions made during the session",
                  items: {
                    type: "object",
                    properties: {
                      title: {type: "string", description: "Short summary (max 100 chars)"},
                      summary: {type: "string", description: "Full description"},
                      status_hint: {type: "string", enum: ["accepted", "proposed", "rejected"]}
                    },
                    required: ["title", "summary"]
                  }
                },
                scope: {type: "string", enum: ["global", "project"], description: "Default scope for facts", default: "project"}
              },
              required: ["facts"]
            }
          }
        ]
      end

      def call(name, arguments)
        case name
        when "memory.recall"
          recall(arguments)
        when "memory.recall_index"
          recall_index(arguments)
        when "memory.recall_details"
          recall_details(arguments)
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
        when "memory.store_extraction"
          store_extraction(arguments)
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

      def recall_index(args)
        scope = args["scope"] || "all"
        results = @recall.query_index(args["query"], limit: args["limit"] || 20, scope: scope)

        total_tokens = results.sum { |r| r[:token_estimate] }

        {
          query: args["query"],
          scope: scope,
          result_count: results.size,
          total_estimated_tokens: total_tokens,
          facts: results.map do |r|
            {
              id: r[:id],
              subject: r[:subject],
              predicate: r[:predicate],
              object_preview: r[:object_preview],
              status: r[:status],
              scope: r[:scope],
              confidence: r[:confidence],
              tokens: r[:token_estimate],
              source: r[:source]
            }
          end
        }
      end

      def recall_details(args)
        fact_ids = args["fact_ids"]
        scope = args["scope"] || "project"

        # Batch fetch detailed explanations
        explanations = fact_ids.map do |fact_id|
          explanation = @recall.explain(fact_id, scope: scope)
          next nil if explanation.is_a?(Core::NullExplanation)

          {
            fact: {
              id: explanation[:fact][:id],
              subject: explanation[:fact][:subject_name],
              predicate: explanation[:fact][:predicate],
              object: explanation[:fact][:object_literal],
              status: explanation[:fact][:status],
              confidence: explanation[:fact][:confidence],
              scope: explanation[:fact][:scope],
              valid_from: explanation[:fact][:valid_from],
              valid_to: explanation[:fact][:valid_to]
            },
            receipts: explanation[:receipts].map { |r|
              {
                quote: r[:quote],
                strength: r[:strength],
                session_id: r[:session_id],
                occurred_at: r[:occurred_at]
              }
            },
            relationships: {
              supersedes: explanation[:supersedes],
              superseded_by: explanation[:superseded_by],
              conflicts: explanation[:conflicts].map { |c| {id: c[:id], status: c[:status]} }
            }
          }
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

      def store_extraction(args)
        scope = args["scope"] || "project"
        store = get_store_for_scope(scope)
        return {error: "Database not available"} unless store

        entities = (args["entities"] || []).map { |e| symbolize_keys(e) }
        facts = (args["facts"] || []).map { |f| symbolize_keys(f) }
        decisions = (args["decisions"] || []).map { |d| symbolize_keys(d) }

        project_path = ENV["CLAUDE_PROJECT_DIR"] || Dir.pwd
        occurred_at = Time.now.utc.iso8601

        searchable_text = build_searchable_text(entities, facts, decisions)
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

      def build_searchable_text(entities, facts, decisions)
        parts = []
        entities.each { |e| parts << "#{e[:type]}: #{e[:name]}" }
        facts.each { |f| parts << "#{f[:subject]} #{f[:predicate]} #{f[:object]} #{f[:quote]}" }
        decisions.each { |d| parts << "#{d[:title]} #{d[:summary]}" }
        parts.join(" ").strip
      end

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
        hash.transform_keys(&:to_sym)
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
