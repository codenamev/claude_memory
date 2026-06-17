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

      # Schema for {predicate, count} entries
      PREDICATE_COUNT_SCHEMA = {
        type: "object",
        properties: {
          predicate: {type: "string"},
          count: {type: "integer"}
        },
        required: ["predicate", "count"]
      }.freeze

      # Schema for per-database stats block returned by memory.stats
      DATABASE_STATS_SCHEMA = {
        type: "object",
        properties: {
          exists: {type: "boolean"},
          schema_version: {type: "integer"},
          facts: {
            type: "object",
            properties: {
              total: {type: "integer"},
              active: {type: "integer"},
              superseded: {type: "integer"},
              top_predicates: {
                type: "array",
                description: "Top 10 predicates by count (known + novel combined)",
                items: PREDICATE_COUNT_SCHEMA
              },
              predicates_known: {
                type: "array",
                description: "Predicates with explicit cardinality policies in PredicatePolicy::POLICIES, sorted by count desc",
                items: PREDICATE_COUNT_SCHEMA
              },
              predicates_novel: {
                type: "array",
                description: "Predicates not in PredicatePolicy::POLICIES, sorted by count desc. Novel predicates with high counts are candidates for promotion to known status with explicit cardinality policies (canonicalization signal).",
                items: PREDICATE_COUNT_SCHEMA
              }
            }
          },
          entities: {
            type: "object",
            properties: {
              total: {type: "integer"},
              by_type: {type: "array", items: {type: "object"}}
            }
          },
          content_items: {type: "object"},
          provenance: {type: "object"},
          conflicts: {type: "object"},
          vec: {type: "object"}
        }
      }.freeze

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
            description: "Get detailed statistics about the memory system (facts by predicate, entities by type, provenance coverage, conflicts, database sizes).",
            inputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: ["all", "global", "project"], description: "Show stats for: all (default), global, or project", default: "all"}
              }
            },
            outputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: ["all", "global", "project"]},
                databases: {
                  type: "object",
                  description: "Per-database stats. Keys are 'global', 'project', or 'legacy' depending on connection mode.",
                  properties: {
                    global: DATABASE_STATS_SCHEMA,
                    project: DATABASE_STATS_SCHEMA,
                    legacy: DATABASE_STATS_SCHEMA
                  }
                }
              },
              required: ["scope", "databases"]
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
            name: "memory.reject_fact",
            description: "Mark a fact as rejected (e.g. a distiller hallucination). Sets status to 'rejected' and closes any open conflicts involving the fact. Use when the user confirms a fact is wrong.",
            inputSchema: {
              type: "object",
              properties: {
                fact_id: {type: "integer", description: "Fact ID to reject"},
                docid: {type: "string", description: "8-char docid (alternative to fact_id)"},
                reason: {type: "string", description: "Why the fact is wrong (recorded in conflict notes)"},
                scope: {type: "string", enum: ["project", "global"], description: "Database scope", default: "project"}
              }
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
                      type: {type: "string", description: "Entity type. Common types: database, framework, language, platform, repo, module, person, service, tool, library, concept. You may use other types if needed."},
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
                      predicate: {type: "string", description: "Relationship type. Known predicates: #{ClaudeMemory::Resolve::PredicatePolicy.known_predicates.join(", ")}. You may use other snake_case predicates for relations that don't fit these — be specific and reuse existing predicates when possible."},
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
                observations: {
                  type: "array",
                  description: "Episodic observations — what happened this session (experimental, observational layer). Complements facts ('what is true') with 'what happened': decisions made, preferences stated, notable actions/outcomes. One per discrete event; embed a reason for decisions/preferences.",
                  items: {
                    type: "object",
                    properties: {
                      body: {type: "string", description: "Concise statement of what happened"},
                      kind: {type: "string", enum: %w[user_statement agent_action tool_result preference decision event], description: "What kind of event (default: event)"},
                      priority: {type: "integer", enum: [1, 2, 3], description: "Internal signal: 1=important, 2=maybe, 3=info (default: 3)"}
                    },
                    required: ["body"]
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
            description: "List facts with predicate=decision from both project and global memory (project first). Returns only `decision`-predicate facts — does not include `uses_database`, `uses_framework`, etc.",
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
            description: "List facts with predicate=convention from both project and global memory (project first). Use this to see project coding conventions alongside user-wide style preferences.",
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
            description: "List architecture facts and stack-shaping constraints (predicates: architecture, uses_database, uses_framework, uses_language, deployment_platform, auth_method) from both project and global memory.",
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
          },
          {
            name: "memory.activity",
            description: "View recent activity events (hook executions, recalls, context injections). Shows what happened behind the scenes for debugging and observability.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 50, description: "Maximum events to return"},
                event_type: {type: "string", enum: %w[hook_ingest hook_context hook_sweep hook_publish recall store_extraction], description: "Filter by event type"},
                since: {type: "string", description: "ISO 8601 timestamp lower bound"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.observations",
            description: "List recent episodic observations — the 'what happened' log that complements facts ('what is true'). Append-only, newest first. Priority is an internal signal (1=important, 2=maybe, 3=info).",
            inputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: %w[project global], description: "Filter by scope; omit for any"},
                limit: {type: "integer", default: 20, description: "Maximum observations to return"},
                important_only: {type: "boolean", default: false, description: "Return only priority-1 (🔴) observations"}
              }
            },
            annotations: READ_ONLY
          },
          {
            name: "memory.promote_observation",
            description: "Promote a corroborated observation into a structured fact (the observation→fact bridge). Refuses observations sighted fewer than the corroboration threshold (anti-hallucination gate). Embed a reason in the object (because…/so that…). Surfaced by the SessionStart 'Observation Reflection' section.",
            inputSchema: {
              type: "object",
              properties: {
                observation_id: {type: "integer", description: "The corroborated observation to promote"},
                predicate: {type: "string", description: "Fact predicate (e.g. decision, convention, architecture)"},
                object: {type: "string", description: "Fact object — include a reason clause"},
                subject: {type: "string", default: "repo", description: "Fact subject (default: repo)"},
                scope: {type: "string", enum: %w[project global], default: "project"}
              },
              required: ["observation_id", "predicate", "object"]
            },
            annotations: WRITE
          }
        ]
      end
    end
  end
end
