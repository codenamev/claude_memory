# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # MCP tool definitions for Claude Memory
    # Pure data structure - no logic, just tool schemas
    module ToolDefinitions
      # Returns array of tool definitions for MCP protocol
      # @return [Array<Hash>] Tool definitions with name, description, and inputSchema
      def self.all
        [
          {
            name: "memory.recall",
            description: "IMPORTANT: Check memory FIRST before reading files or exploring code. Recalls facts matching a query from distilled knowledge in both global and project databases. Use this to find existing knowledge about modules, patterns, decisions, and conventions before resorting to file reads or code searches.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query for existing knowledge (e.g., 'authentication flow', 'error handling', 'database setup')"},
                limit: {type: "integer", description: "Max results", default: 10},
                scope: {type: "string", enum: ["all", "global", "project"], description: "Filter by scope: 'all' (default), 'global', or 'project'", default: "all"}
              },
              required: ["query"]
            }
          },
          {
            name: "memory.recall_index",
            description: "Layer 1: CHECK MEMORY FIRST with this lightweight search. Returns fact previews, IDs, and token costs without full details. Use before exploring code to see what knowledge already exists. Follow up with memory.recall_details for specific facts.",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query for existing knowledge (e.g., 'client errors', 'database choice')"},
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
            name: "memory.stats",
            description: "Get detailed statistics about the memory system (facts by predicate, entities by type, provenance coverage, conflicts, database sizes)",
            inputSchema: {
              type: "object",
              properties: {
                scope: {type: "string", enum: ["all", "global", "project"], description: "Show stats for: all (default), global, or project", default: "all"}
              }
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
          },
          {
            name: "memory.decisions",
            description: "Quick access to architectural decisions, constraints, and rules. Use BEFORE implementing features to understand existing decisions and constraints.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 10, description: "Maximum results to return"}
              }
            }
          },
          {
            name: "memory.conventions",
            description: "Quick access to coding conventions and style preferences (global scope). Check BEFORE writing code to follow established patterns.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 20, description: "Maximum results to return"}
              }
            }
          },
          {
            name: "memory.architecture",
            description: "Quick access to framework choices and architectural patterns. Check FIRST when working with frameworks or making architectural decisions.",
            inputSchema: {
              type: "object",
              properties: {
                limit: {type: "integer", default: 10, description: "Maximum results to return"}
              }
            }
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
            }
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
            }
          },
          {
            name: "memory.recall_semantic",
            description: "Search facts using semantic similarity (finds conceptually related facts using vector embeddings)",
            inputSchema: {
              type: "object",
              properties: {
                query: {type: "string", description: "Search query"},
                mode: {type: "string", enum: ["vector", "text", "both"], default: "both", description: "Search mode: vector (embeddings), text (FTS), or both (hybrid)"},
                limit: {type: "integer", default: 10, description: "Maximum results to return"},
                scope: {type: "string", enum: ["all", "global", "project"], default: "all", description: "Filter by scope"}
              },
              required: ["query"]
            }
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
                scope: {type: "string", enum: ["all", "global", "project"], default: "all", description: "Filter by scope"}
              },
              required: ["concepts"]
            }
          },
          {
            name: "memory.check_setup",
            description: "Check if ClaudeMemory is properly initialized. CALL THIS FIRST if memory tools fail or on first use. Returns initialization status, version info, and actionable recommendations.",
            inputSchema: {
              type: "object",
              properties: {}
            }
          }
        ]
      end
    end
  end
end
