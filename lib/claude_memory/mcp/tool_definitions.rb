# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # MCP tool definitions for Claude Memory
    # Pure data structure - no logic, just tool schemas
    module ToolDefinitions
      # Annotations for read-only query tools (safe to call anytime)
      READ_ONLY = {readOnlyHint: true, idempotentHint: true, destructiveHint: false}.freeze

      # Annotations for state-changing but non-destructive tools
      WRITE = {readOnlyHint: false, idempotentHint: false, destructiveHint: false}.freeze

      # Annotations for idempotent writes (safe to retry)
      WRITE_IDEMPOTENT = {readOnlyHint: false, idempotentHint: true, destructiveHint: false}.freeze

      # Returns array of tool definitions for MCP protocol
      # @return [Array<Hash>] Tool definitions with name, description, and inputSchema
      def self.all
        [
          {
            name: "memory.recall",
            description: "Search facts matching a query from both global and project memory databases. Returns full facts with provenance (~800 tokens/result, ~300 with compact: true). For token-efficient browsing, use memory.recall_index first (~200 tokens/result), then memory.recall_details for selected facts.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query for existing knowledge (e.g., 'authentication flow', 'error handling', 'database setup')"},
                intent: {type: "string", description: "Optional intent to disambiguate the query (e.g., 'migration' or 'performance' when query is 'database'). Steers search without replacing the query."},
                limit: {type: "integer", description: "Max results", default: 10},
                scope: {type: "string", enum: ["all", "global", "project"], description: "Filter by scope: 'all' (default), 'global', or 'project'", default: "all"},
                compact: {type: "boolean", description: "Omit provenance receipts for ~60% smaller responses (~800 → ~300 tokens/result)", default: false}
              },
              required: ["query"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.recall_index",
            description: "Lightweight search returning fact previews, IDs, and token costs (~200 tokens/result). Step 1 of progressive disclosure: browse results here, then call memory.recall_details with selected fact IDs for full information (~500 tokens/fact). Saves ~60% tokens vs memory.recall when you only need a few facts.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query for existing knowledge (e.g., 'client errors', 'database choice')"},
                intent: {type: "string", description: "Optional intent to disambiguate the query (e.g., 'schema' or 'optimization' when query is 'database'). Steers search without replacing the query."},
                limit: {type: "integer", description: "Maximum results to return", default: 20},
                scope: {type: "string", enum: ["all", "global", "project"], description: "Scope: 'all' (both), 'global' (user-wide), 'project' (current only)", default: "all"}
              },
              required: ["query"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.recall_details",
            description: "Fetch full details for specific fact IDs (~500 tokens/fact). Step 2 of progressive disclosure: use after memory.recall_index to get provenance and metadata for selected facts only.",
            inputSchema: {
              type: "object",
              properties: {
                fact_ids: {type: "array", items: {type: "integer"}, description: "Fact IDs from memory.recall_index"},
                scope: {type: "string", enum: ["project", "global"], description: "Database to query", default: "project"}
              },
              required: ["fact_ids"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.explain",
            description: "Get detailed explanation of a fact with provenance",
            inputSchema: {
              type: "object",
              properties: {
                fact_id: {description: "Fact ID (integer) or docid (8-char hex string) to explain"},
                scope: {type: "string", enum: ["global", "project"], description: "Which database to look in", default: "project"}
              },
              required: ["fact_id"]
            },
            annotations: READ_ONLY
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
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.conflicts",
            description: "List open conflicts from both databases",
            inputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: ["all", "global", "project"], default: "all"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.sweep_now",
            description: "Run maintenance sweep on a database. Use escalate: true for guaranteed progress (normal → aggressive → fallback).",
            inputSchema: {
              type: "object",
              properties: {
                budget_seconds: {type: "integer", default: 5},
                scope: {type: "string", enum: ["global", "project"], default: "project"},
                escalate: {type: "boolean", default: false, description: "Enable three-level escalation (normal → aggressive → fallback) to guarantee progress"}
              }
            },
            annotations: WRITE
          },
          {
            name: "memory.status",
            description: "Get memory system status for both databases",
            inputSchema: {
              type: "object",
              properties: {}
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.stats",
            description: "Get detailed statistics about the memory system (facts by predicate, entities by type, provenance coverage, conflicts, database sizes)",
            inputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: ["all", "global", "project"], description: "Show stats for: all (default), global, or project", default: "all"}
              }
            },
            annotations: READ_ONLY
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
            },
            annotations: WRITE_IDEMPOTENT
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
            },
            annotations: WRITE
          },
          {
            name: "memory.decisions",
            description: "List architectural decisions, constraints, and rules.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 10, description: "Maximum results to return"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.conventions",
            description: "List coding conventions and style preferences from global memory.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 20, description: "Maximum results to return"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.architecture",
            description: "List framework choices and architectural patterns.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 10, description: "Maximum results to return"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.facts_by_tool",
            description: "Find facts discovered using a specific tool (Read, Edit, Bash, etc.)",
            inputSchema: {
              type: "object",
              properties: {
                tool_name: {type: "string", description: "Tool name (Read, Edit, Bash, etc.)"},
                limit: {type: "integer", default: 20, description: "Maximum results to return"},
                scope: {type: "string", enum: ["all", "global", "project"], default: "all", description: "Filter by scope"}
              },
              required: ["tool_name"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.facts_by_context",
            description: "Find facts learned in specific context (branch, directory)",
            inputSchema: {
              type: "object",
              properties: {
                git_branch: {type: "string", description: "Git branch name"},
                cwd: {type: "string", description: "Working directory path"},
                limit: {type: "integer", default: 20, description: "Maximum results to return"},
                scope: {type: "string", enum: ["all", "global", "project"], default: "all", description: "Filter by scope"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.recall_semantic",
            description: "Search facts using semantic similarity (finds conceptually related facts using vector embeddings). ~800 tokens/result, ~300 with compact: true.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query"},
                intent: {type: "string", description: "Optional intent to disambiguate the query (e.g., 'security' when query is 'authentication'). Disables BM25 shortcut to ensure vector search runs."},
                mode: {type: "string", enum: ["vector", "text", "both"], default: "both", description: "Search mode: vector (embeddings), text (FTS), or both (hybrid)"},
                limit: {type: "integer", default: 10, description: "Maximum results to return"},
                scope: {type: "string", enum: ["all", "global", "project"], default: "all", description: "Filter by scope"},
                compact: {type: "boolean", description: "Omit provenance receipts for ~60% smaller responses (~800 → ~300 tokens/result)", default: false},
                explain: {type: "boolean", description: "Include per-result score traces showing FTS rank, vector similarity, and RRF contribution", default: false}
              },
              required: ["query"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.search_concepts",
            description: "Search for facts matching ALL of the provided concepts (AND query). Ranks by average similarity across all concepts.",
            inputSchema: {
              type: "object",
              properties: {
                concepts: {
                  type: "array",
                  items: {type: "string"},
                  minItems: 2,
                  maxItems: 5,
                  description: "2-5 concepts that must all be present"
                },
                limit: {type: "integer", default: 10, description: "Maximum results to return"},
                scope: {type: "string", enum: ["all", "global", "project"], default: "all", description: "Filter by scope"},
                compact: {type: "boolean", description: "Omit provenance receipts for ~60% smaller responses (~800 → ~300 tokens/result)", default: false}
              },
              required: ["concepts"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.fact_graph",
            description: "Build a dependency graph showing how facts relate through supersession and conflict links. Returns nodes (facts) and edges (supersedes/conflicts).",
            inputSchema: {
              type: "object",
              properties: {
                fact_id: {type: "integer", description: "Root fact ID to start traversal from"},
                depth: {type: "integer", description: "Maximum BFS traversal depth (1-5)", default: 2},
                scope: {type: "string", enum: ["global", "project"], description: "Which database to search", default: "project"}
              },
              required: ["fact_id"]
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.undistilled",
            description: "List content items not yet deeply distilled. Returns raw transcript text for knowledge extraction.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 3, description: "Max items to return"},
                min_length: {type: "integer", default: 200, description: "Min text length (skip tiny deltas)"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.mark_distilled",
            description: "Mark a content item as distilled after extracting facts from it.",
            inputSchema: {
              type: "object",
              properties: {
                content_item_id: {type: "integer", description: "ID of the distilled content item"},
                facts_extracted: {type: "integer", default: 0, description: "Number of facts extracted"}
              },
              required: ["content_item_id"]
            },
            annotations: WRITE_IDEMPOTENT
          },
          {
            name: "memory.check_setup",
            description: "Check ClaudeMemory initialization status. Returns version info, issues found, and recommendations.",
            inputSchema: {
              type: "object",
              properties: {}
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.list_projects",
            description: "List all known memory databases with fact counts and status. Shows global database, current project, and other projects discovered from promoted facts. Helps discover available search scopes before querying.",
            inputSchema: {
              type: "object",
              properties: {}
            },
            annotations: READ_ONLY
          }
        ]
      end
    end
  end
end
