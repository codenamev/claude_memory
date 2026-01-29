# frozen_string_literal: true

require "json"
require "digest"
require_relative "tool_helpers"
require_relative "response_formatter"

module ClaudeMemory
  module MCP
    class Tools
      include ToolHelpers

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
        when "memory.stats"
          stats(arguments)
        when "memory.promote"
          promote(arguments)
        when "memory.store_extraction"
          store_extraction(arguments)
        when "memory.decisions"
          decisions(arguments)
        when "memory.conventions"
          conventions(arguments)
        when "memory.architecture"
          architecture(arguments)
        when "memory.facts_by_tool"
          facts_by_tool(arguments)
        when "memory.facts_by_context"
          facts_by_context(arguments)
        when "memory.recall_semantic"
          recall_semantic(arguments)
        when "memory.search_concepts"
          search_concepts(arguments)
        when "memory.check_setup"
          check_setup
        else
          {error: "Unknown tool: #{name}"}
        end
      end

      private

      def recall(args)
        # Check if databases exist before querying
        return database_not_found_error(StandardError.new("Database not initialized")) unless databases_exist?

        scope = extract_scope(args)
        limit = extract_limit(args)
        results = @recall.query(args["query"], limit: limit, scope: scope)
        ResponseFormatter.format_recall_results(results)
      rescue Sequel::DatabaseError, Sequel::DatabaseConnectionError, SQLite3::CantOpenException, Errno::ENOENT => e
        database_not_found_error(e)
      end

      def recall_index(args)
        scope = extract_scope(args)
        limit = extract_limit(args, default: 20)
        results = @recall.query_index(args["query"], limit: limit, scope: scope)
        ResponseFormatter.format_index_results(args["query"], scope, results)
      end

      def recall_details(args)
        fact_ids = args["fact_ids"]
        scope = args["scope"] || "project"

        # Batch fetch detailed explanations
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

      def sweep_now(args)
        scope = args["scope"] || "project"
        store = get_store_for_scope(scope)
        return {error: "Database not available"} unless store

        sweeper = Sweep::Sweeper.new(store)
        stats = sweeper.run!(budget_seconds: args["budget_seconds"] || 5)
        ResponseFormatter.format_sweep_stats(scope, stats)
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

      def stats(args)
        scope = args["scope"] || "all"
        result = {scope: scope, databases: {}}

        if @manager
          if scope == "all" || scope == "global"
            if @manager.global_exists?
              @manager.ensure_global!
              result[:databases][:global] = detailed_stats(@manager.global_store)
            else
              result[:databases][:global] = {exists: false}
            end
          end

          if scope == "all" || scope == "project"
            if @manager.project_exists?
              @manager.ensure_project!
              result[:databases][:project] = detailed_stats(@manager.project_store)
            else
              result[:databases][:project] = {exists: false}
            end
          end
        else
          result[:databases][:legacy] = detailed_stats(@legacy_store)
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

        config = Configuration.new
        project_path = config.project_dir
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
        Core::TextBuilder.build_searchable_text(entities, facts, decisions)
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
        Core::TextBuilder.symbolize_keys(hash)
      end

      def get_store_for_scope(scope)
        if @manager
          @manager.store_for_scope(scope)
        else
          @legacy_store
        end
      end

      def decisions(args)
        return {error: "Decisions shortcut requires StoreManager"} unless @manager

        results = Recall.recent_decisions(@manager, limit: args["limit"] || 10)
        format_shortcut_results(results, "decisions")
      end

      def conventions(args)
        return {error: "Conventions shortcut requires StoreManager"} unless @manager

        results = Recall.conventions(@manager, limit: args["limit"] || 20)
        format_shortcut_results(results, "conventions")
      end

      def architecture(args)
        return {error: "Architecture shortcut requires StoreManager"} unless @manager

        results = Recall.architecture_choices(@manager, limit: args["limit"] || 10)
        format_shortcut_results(results, "architecture")
      end

      def format_shortcut_results(results, category)
        ResponseFormatter.format_shortcut_results(category, results)
      end

      def facts_by_tool(args)
        tool_name = args["tool_name"]
        scope = extract_scope(args)
        limit = extract_limit(args, default: 20)

        results = @recall.facts_by_tool(tool_name, limit: limit, scope: scope)

        {
          tool_name: tool_name,
          scope: scope,
          count: results.size,
          facts: results.map { |r| format_result(r) }
        }
      end

      def facts_by_context(args)
        scope = extract_scope(args)
        limit = extract_limit(args, default: 20)

        if args["git_branch"]
          results = @recall.facts_by_branch(args["git_branch"], limit: limit, scope: scope)
          context_type = "git_branch"
          context_value = args["git_branch"]
        elsif args["cwd"]
          results = @recall.facts_by_directory(args["cwd"], limit: limit, scope: scope)
          context_type = "cwd"
          context_value = args["cwd"]
        else
          return {error: "Must provide either git_branch or cwd parameter"}
        end

        {
          context_type: context_type,
          context_value: context_value,
          scope: scope,
          count: results.size,
          facts: results.map { |r| format_result(r) }
        }
      end

      def recall_semantic(args)
        query = args["query"]
        mode = (args["mode"] || "both").to_sym
        scope = extract_scope(args)
        limit = extract_limit(args)

        results = @recall.query_semantic(query, limit: limit, scope: scope, mode: mode)
        ResponseFormatter.format_semantic_results(query, mode.to_s, scope, results)
      end

      def search_concepts(args)
        concepts = args["concepts"]
        scope = extract_scope(args)
        limit = extract_limit(args)

        return {error: "Must provide 2-5 concepts"} unless (2..5).cover?(concepts.size)

        results = @recall.query_concepts(concepts, limit: limit, scope: scope)
        ResponseFormatter.format_concept_results(concepts, scope, results)
      end

      def databases_exist?
        if @manager
          # For dual-database mode, at least global database should exist
          config = Configuration.new
          File.exist?(config.global_db_path)
        elsif @legacy_store
          # For legacy mode, check if the database file exists
          # Extract the database path from the store's connection
          db_path = @legacy_store.db.opts[:database]
          db_path && File.exist?(db_path)
        else
          false
        end
      end

      def database_not_found_error(error)
        {
          error: "Database not found or not accessible",
          message: "ClaudeMemory may not be initialized. Run memory.check_setup for detailed status.",
          details: error.message,
          recommendations: [
            "Run memory.check_setup to diagnose the issue",
            "If not initialized, run: claude-memory init",
            "For help: claude-memory doctor"
          ]
        }
      end

      def check_setup
        issues = []
        warnings = []
        config = Configuration.new

        # Check global database
        global_db_exists = File.exist?(config.global_db_path)
        unless global_db_exists
          issues << "Global database not found at #{config.global_db_path}"
        end

        # Check project database
        project_db_exists = File.exist?(config.project_db_path)
        unless project_db_exists
          warnings << "Project database not found at #{config.project_db_path}"
        end

        # Check for CLAUDE.md and version
        claude_md_path = ".claude/CLAUDE.md"
        claude_md_exists = File.exist?(claude_md_path)
        current_version = nil
        version_status = nil

        if claude_md_exists
          content = File.read(claude_md_path)
          if content.include?("ClaudeMemory")
            # Extract version from HTML comment
            if content =~ /<!-- ClaudeMemory v([\d.]+) -->/
              current_version = $1
              if current_version == ClaudeMemory::VERSION
                version_status = "up_to_date"
              else
                version_status = "outdated"
                warnings << "Configuration version (v#{current_version}) is older than ClaudeMemory (v#{ClaudeMemory::VERSION}). Consider running upgrade."
              end
            else
              version_status = "no_version_marker"
              warnings << "CLAUDE.md has ClaudeMemory section but no version marker"
            end
          else
            warnings << "CLAUDE.md exists but no ClaudeMemory configuration found"
          end
        else
          warnings << "No .claude/CLAUDE.md found"
        end

        # Check hooks configuration
        hooks_configured = false
        settings_paths = [".claude/settings.json", ".claude/settings.local.json"]
        settings_paths.each do |path|
          if File.exist?(path)
            begin
              config_data = JSON.parse(File.read(path))
              if config_data["hooks"]&.any?
                hooks_configured = true
                break
              end
            rescue JSON::ParserError
              warnings << "Invalid JSON in #{path}"
            end
          end
        end

        unless hooks_configured
          warnings << "No hooks configured for automatic ingestion"
        end

        # Determine overall status
        initialized = global_db_exists && claude_md_exists
        status = if initialized && version_status == "up_to_date"
          "healthy"
        elsif initialized && version_status == "outdated"
          "needs_upgrade"
        elsif global_db_exists && !claude_md_exists
          "partially_initialized"
        else
          "not_initialized"
        end

        # Generate recommendations
        recommendations = []
        if !initialized
          recommendations << "Run: claude-memory init"
          recommendations << "This will create databases, configure hooks, and set up CLAUDE.md"
        elsif version_status == "outdated"
          recommendations << "Run: claude-memory upgrade (when available)"
          recommendations << "Or manually run: claude-memory init to update CLAUDE.md"
        elsif warnings.any?
          recommendations << "Run: claude-memory doctor --fix (when available)"
          recommendations << "Or check individual issues and fix manually"
        end

        {
          status: status,
          initialized: initialized,
          version: {
            current: current_version || "unknown",
            latest: ClaudeMemory::VERSION,
            status: version_status || "unknown"
          },
          components: {
            global_database: global_db_exists,
            project_database: project_db_exists,
            claude_md: claude_md_exists,
            hooks_configured: hooks_configured
          },
          issues: issues,
          warnings: warnings,
          recommendations: recommendations
        }
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

      def detailed_stats(store)
        result = {exists: true}

        # Facts statistics
        total_facts = store.facts.count
        active_facts = store.facts.where(status: "active").count
        superseded_facts = store.facts.where(status: "superseded").count

        result[:facts] = {
          total: total_facts,
          active: active_facts,
          superseded: superseded_facts
        }

        # Top predicates
        if active_facts > 0
          top_predicates = store.db[:facts]
            .where(status: "active")
            .group_and_count(:predicate)
            .order(Sequel.desc(:count))
            .limit(10)
            .all
            .map { |row| {predicate: row[:predicate], count: row[:count]} }

          result[:facts][:top_predicates] = top_predicates
        end

        # Entities by type
        entity_counts = store.db[:entities]
          .group_and_count(:type)
          .order(Sequel.desc(:count))
          .all
          .map { |row| {type: row[:type], count: row[:count]} }

        result[:entities] = {
          total: store.entities.count,
          by_type: entity_counts
        }

        # Content items
        content_count = store.content_items.count
        result[:content_items] = {
          total: content_count
        }

        if content_count > 0
          first_date = store.content_items.min(:occurred_at)
          last_date = store.content_items.max(:occurred_at)
          result[:content_items][:date_range] = {
            first: first_date,
            last: last_date
          }
        end

        # Provenance coverage
        if active_facts > 0
          facts_with_provenance = store.db[:provenance]
            .join(:facts, id: :fact_id)
            .where(Sequel[:facts][:status] => "active")
            .select(Sequel[:provenance][:fact_id])
            .distinct
            .count

          coverage_percentage = (facts_with_provenance * 100.0 / active_facts).round(1)

          result[:provenance] = {
            facts_with_sources: facts_with_provenance,
            total_active_facts: active_facts,
            coverage_percentage: coverage_percentage
          }
        else
          result[:provenance] = {
            facts_with_sources: 0,
            total_active_facts: 0,
            coverage_percentage: 0
          }
        end

        # Conflicts
        open_conflicts = store.conflicts.where(status: "open").count
        resolved_conflicts = store.conflicts.where(status: "resolved").count

        result[:conflicts] = {
          open: open_conflicts,
          resolved: resolved_conflicts,
          total: open_conflicts + resolved_conflicts
        }

        # Schema version
        result[:schema_version] = store.schema_version

        result
      end
    end
  end
end
