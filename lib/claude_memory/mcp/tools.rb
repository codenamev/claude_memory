# frozen_string_literal: true

require "json"
require "digest"
require_relative "tool_helpers"
require_relative "response_formatter"
require_relative "tool_definitions"
require_relative "setup_status_analyzer"

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
        ToolDefinitions.all
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
        when "memory.fact_graph"
          fact_graph(arguments)
        when "memory.check_setup"
          check_setup
        when "memory.list_projects"
          list_projects
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
        compact = args["compact"] == true
        query = args["query"]
        results = @recall.query(query, limit: limit, scope: scope, include_raw_text: !compact)
        ResponseFormatter.format_recall_results(results, compact: compact, query: query)
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
        budget = args["budget_seconds"] || 5
        stats = if args["escalate"]
          sweeper.run_with_escalation!(budget_seconds: budget)
        else
          sweeper.run!(budget_seconds: budget)
        end
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
        ResponseFormatter.format_tool_facts(tool_name, scope, results)
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

        ResponseFormatter.format_context_facts(context_type, context_value, scope, results)
      end

      def recall_semantic(args)
        query = args["query"]
        mode = (args["mode"] || "both").to_sym
        scope = extract_scope(args)
        limit = extract_limit(args)
        compact = args["compact"] == true

        results = @recall.query_semantic(query, limit: limit, scope: scope, mode: mode)
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

      def databases_exist?
        if @manager
          # For dual-database mode, check if either database exists
          config = Configuration.new
          File.exist?(config.global_db_path) || File.exist?(config.project_db_path)
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

        global_db_exists = check_global_database(config, issues)
        project_db_exists = check_project_database(config, warnings)
        current_version, version_status, claude_md_exists = check_claude_md_version(warnings)
        hooks_configured = check_hooks_configuration(warnings)

        build_setup_result(
          global_db_exists, project_db_exists, claude_md_exists,
          hooks_configured, current_version, version_status,
          issues, warnings
        )
      end

      def check_global_database(config, issues)
        exists = File.exist?(config.global_db_path)
        issues << "Global database not found at #{config.global_db_path}" unless exists
        exists
      end

      def check_project_database(config, warnings)
        exists = File.exist?(config.project_db_path)
        warnings << "Project database not found at #{config.project_db_path}" unless exists
        exists
      end

      def check_claude_md_version(warnings)
        claude_md_path = ".claude/CLAUDE.md"
        unless File.exist?(claude_md_path)
          warnings << "No .claude/CLAUDE.md found"
          return [nil, nil, false]
        end

        content = File.read(claude_md_path)
        unless content.include?("ClaudeMemory")
          warnings << "CLAUDE.md exists but no ClaudeMemory configuration found"
          return [nil, nil, true]
        end

        current_version = SetupStatusAnalyzer.extract_version(content)
        unless current_version
          warnings << "CLAUDE.md has ClaudeMemory section but no version marker"
          return [nil, "no_version_marker", true]
        end

        version_status = SetupStatusAnalyzer.determine_version_status(current_version, ClaudeMemory::VERSION)
        if version_status == "outdated"
          warnings << "Configuration version (v#{current_version}) is older than ClaudeMemory (v#{ClaudeMemory::VERSION}). Consider running upgrade."
        end

        [current_version, version_status, true]
      end

      def check_hooks_configuration(warnings)
        settings_paths = [".claude/settings.json", ".claude/settings.local.json"]
        settings_paths.each do |path|
          next unless File.exist?(path)
          begin
            config_data = JSON.parse(File.read(path))
            return true if config_data["hooks"]&.any?
          rescue JSON::ParserError
            warnings << "Invalid JSON in #{path}"
          end
        end

        warnings << "No hooks configured for automatic ingestion"
        false
      end

      def build_setup_result(global_db_exists, project_db_exists, claude_md_exists, hooks_configured, current_version, version_status, issues, warnings)
        initialized = global_db_exists && claude_md_exists
        status = SetupStatusAnalyzer.determine_status(global_db_exists, claude_md_exists, version_status)
        recommendations = SetupStatusAnalyzer.generate_recommendations(initialized, version_status, warnings.any?)

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

      def list_projects
        result = {global: nil, current_project: nil, other_projects: []}

        if @manager
          result[:global] = list_global_database
          result[:current_project] = list_current_project
          result[:other_projects] = discover_other_projects
        elsif @legacy_store
          result[:global] = {
            exists: true,
            path: @legacy_store.db.opts[:database],
            facts_active: @legacy_store.facts.where(status: "active").count,
            entities: @legacy_store.entities.count
          }
        end

        result[:project_count] = 1 + result[:other_projects].size
        result
      end

      def list_global_database
        if @manager.global_exists?
          @manager.ensure_global!
          store = @manager.global_store
          {
            exists: true,
            path: @manager.global_db_path,
            facts_active: store.facts.where(status: "active").count,
            facts_total: store.facts.count,
            entities: store.entities.count
          }
        else
          {exists: false, path: @manager.global_db_path}
        end
      end

      def list_current_project
        if @manager.project_exists?
          @manager.ensure_project!
          store = @manager.project_store
          {
            exists: true,
            path: @manager.project_path,
            db_path: @manager.project_db_path,
            facts_active: store.facts.where(status: "active").count,
            facts_total: store.facts.count,
            entities: store.entities.count
          }
        else
          {exists: false, path: @manager.project_path, db_path: @manager.project_db_path}
        end
      end

      def discover_other_projects
        return [] unless @manager.global_exists?

        @manager.ensure_global!
        global = @manager.global_store

        # Find project paths from promoted facts
        promoted_paths = global.facts
          .where(Sequel.like(:created_from, "promoted:%"))
          .select(:created_from)
          .distinct
          .all
          .filter_map { |f|
            match = f[:created_from]&.match(/\Apromoted:(.+):\d+\z/)
            match[1] if match
          }
          .uniq

        # Also check for project_path values on facts
        fact_paths = global.facts
          .exclude(project_path: nil)
          .select(:project_path)
          .distinct
          .all
          .map { |f| f[:project_path] }

        all_paths = (promoted_paths + fact_paths).uniq
        current = @manager.project_path

        all_paths.filter_map { |path|
          next if path == current

          db_path = File.join(path, ".claude", "memory.sqlite3")
          entry = {path: path, db_path: db_path, exists: File.exist?(db_path)}

          if entry[:exists]
            begin
              temp_store = Store::SQLiteStore.new(db_path)
              entry[:facts_active] = temp_store.facts.where(status: "active").count
              entry[:facts_total] = temp_store.facts.count
              entry[:entities] = temp_store.entities.count
              temp_store.close
            rescue Sequel::DatabaseError, Extralite::Error, IOError => _e
              entry[:error] = "Could not read database"
            end
          end

          entry
        }
      end

      def db_stats(store)
        stats = {
          exists: true,
          facts_total: store.facts.count,
          facts_active: store.facts.where(status: "active").count,
          content_items: store.content_items.count,
          open_conflicts: store.conflicts.where(status: "open").count,
          schema_version: store.schema_version
        }

        vec_index = store.vector_index
        stats[:vec_available] = vec_index.available?
        stats[:vec_indexed] = vec_index.coverage_stats[:vec_indexed] if vec_index.available?

        if fts_legacy?(store)
          stats[:fts_legacy] = true
          stats[:optimization_hint] = "Run 'claude-memory compact' to reduce database size by ~40%"
        end

        stats
      end

      def fts_legacy?(store)
        row = store.db.fetch("SELECT sql FROM sqlite_master WHERE name = 'content_fts' AND type = 'table'").first
        row && !row[:sql].to_s.include?("content=''")
      rescue
        false
      end

      def detailed_stats(store)
        active_facts = store.facts.where(status: "active").count

        stats = {
          exists: true,
          facts: fact_stats(store, active_facts),
          entities: entity_stats(store),
          content_items: content_stats(store),
          provenance: provenance_stats(store, active_facts),
          conflicts: conflict_stats(store),
          schema_version: store.schema_version
        }

        stats[:vec] = vec_stats(store, active_facts)

        stats
      end

      def fact_stats(store, active_facts)
        stats = {
          total: store.facts.count,
          active: active_facts,
          superseded: store.facts.where(status: "superseded").count
        }

        if active_facts > 0
          stats[:top_predicates] = store.db[:facts]
            .where(status: "active")
            .group_and_count(:predicate)
            .order(Sequel.desc(:count))
            .limit(10)
            .all
            .map { |row| {predicate: row[:predicate], count: row[:count]} }
        end

        stats
      end

      def entity_stats(store)
        {
          total: store.entities.count,
          by_type: store.db[:entities]
            .group_and_count(:type)
            .order(Sequel.desc(:count))
            .all
            .map { |row| {type: row[:type], count: row[:count]} }
        }
      end

      def content_stats(store)
        count = store.content_items.count
        stats = {total: count}

        if count > 0
          stats[:date_range] = {
            first: store.content_items.min(:occurred_at),
            last: store.content_items.max(:occurred_at)
          }
        end

        stats
      end

      def provenance_stats(store, active_facts)
        return {facts_with_sources: 0, total_active_facts: 0, coverage_percentage: 0} if active_facts == 0

        facts_with_provenance = store.db[:provenance]
          .join(:facts, id: :fact_id)
          .where(Sequel[:facts][:status] => "active")
          .select(Sequel[:provenance][:fact_id])
          .distinct
          .count

        {
          facts_with_sources: facts_with_provenance,
          total_active_facts: active_facts,
          coverage_percentage: (facts_with_provenance * 100.0 / active_facts).round(1)
        }
      end

      def vec_stats(store, _active_facts)
        vec_index = store.vector_index
        result = {available: vec_index.available?}
        result.merge!(vec_index.coverage_stats) if vec_index.available?
        result
      end

      def conflict_stats(store)
        open = store.conflicts.where(status: "open").count
        resolved = store.conflicts.where(status: "resolved").count

        {open: open, resolved: resolved, total: open + resolved}
      end
    end
  end
end
