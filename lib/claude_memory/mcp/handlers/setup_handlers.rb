# frozen_string_literal: true

module ClaudeMemory
  module MCP
    module Handlers
      # Setup and discovery tool handlers
      module SetupHandlers
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

        private

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
      end
    end
  end
end
