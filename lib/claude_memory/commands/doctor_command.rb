# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Commands
    # Performs system health checks for ClaudeMemory
    # Checks databases, snapshots, hooks configuration
    class DoctorCommand < BaseCommand
      def call(_args)
        issues = []
        warnings = []

        stdout.puts "Claude Memory Doctor\n"
        stdout.puts "=" * 40

        manager = ClaudeMemory::Store::StoreManager.new

        stdout.puts "\n## Global Database"
        check_database(manager.global_db_path, "global", issues, warnings)

        stdout.puts "\n## Project Database"
        check_database(manager.project_db_path, "project", issues, warnings)

        manager.close

        check_snapshot(warnings)
        check_claude_md(warnings)
        check_hooks_config(warnings)

        stdout.puts

        if warnings.any?
          stdout.puts "Warnings:"
          warnings.each { |w| stdout.puts "  ⚠ #{w}" }
          stdout.puts
        end

        if issues.any?
          stdout.puts "Issues:"
          issues.each { |i| stderr.puts "  ✗ #{i}" }
          stdout.puts
          stdout.puts "Run 'claude-memory init' to set up."
          return 1
        end

        stdout.puts "All checks passed!"
        0
      end

      private

      def check_database(db_path, label, issues, warnings)
        if File.exist?(db_path)
          stdout.puts "✓ #{label.capitalize} database exists: #{db_path}"
          begin
            store = ClaudeMemory::Store::SQLiteStore.new(db_path)
            stdout.puts "  Schema version: #{store.schema_version}"

            fact_count = store.facts.count
            stdout.puts "  Facts: #{fact_count}"

            content_count = store.content_items.count
            stdout.puts "  Content items: #{content_count}"

            conflict_count = store.conflicts.where(status: "open").count
            if conflict_count > 0
              warnings << "#{label}: #{conflict_count} open conflict(s) need resolution"
            end
            stdout.puts "  Open conflicts: #{conflict_count}"

            last_ingest = store.content_items.max(:ingested_at)
            if last_ingest
              stdout.puts "  Last ingest: #{last_ingest}"
            elsif label == "project"
              warnings << "#{label}: No content has been ingested yet"
            end

            # Check for stuck operations
            tracker = ClaudeMemory::Infrastructure::OperationTracker.new(store)
            stuck_ops = tracker.stuck_operations
            if stuck_ops.any?
              stuck_ops.each do |op|
                warnings << "#{label}: Stuck operation '#{op[:operation_type]}' (started #{op[:started_at]}). Run 'claude-memory recover' to reset."
              end
            end
            stdout.puts "  Stuck operations: #{stuck_ops.size}"

            # Run schema validation
            validator = ClaudeMemory::Infrastructure::SchemaValidator.new(store)
            validation = validator.validate
            stdout.puts "  Schema health: #{validation[:valid] ? "healthy" : "issues detected"}"

            # Report validation issues
            if validation[:issues].any?
              validation[:issues].each do |issue|
                if issue[:severity] == "error"
                  issues << "#{label}: #{issue[:message]}"
                else
                  warnings << "#{label}: #{issue[:message]}"
                end
              end
            end

            store.close
          rescue => e
            issues << "#{label} database error: #{e.message}"
          end
        elsif label == "global"
          issues << "Global database not found: #{db_path}"
        else
          warnings << "Project database not found: #{db_path} (run 'claude-memory init')"
        end
      end

      def check_snapshot(warnings)
        if File.exist?(".claude/rules/claude_memory.generated.md")
          stdout.puts "✓ Published snapshot exists"
        else
          warnings << "No published snapshot found. Run 'claude-memory publish'"
        end
      end

      def check_claude_md(warnings)
        if File.exist?(".claude/CLAUDE.md")
          content = File.read(".claude/CLAUDE.md")
          if content.include?("claude_memory.generated.md")
            stdout.puts "✓ CLAUDE.md imports snapshot"
          else
            warnings << "CLAUDE.md does not import snapshot"
          end
        else
          warnings << "No .claude/CLAUDE.md found"
        end
      end

      def check_hooks_config(warnings)
        settings_path = ".claude/settings.json"
        local_settings_path = ".claude/settings.local.json"

        hooks_found = false

        [settings_path, local_settings_path].each do |path|
          next unless File.exist?(path)

          begin
            config = JSON.parse(File.read(path))
            if config["hooks"]&.any?
              hooks_found = true
              stdout.puts "✓ Hooks configured in #{path}"

              expected_hooks = %w[Stop SessionStart PreCompact SessionEnd]
              missing = expected_hooks - config["hooks"].keys
              if missing.any?
                warnings << "Missing recommended hooks in #{path}: #{missing.join(", ")}"
              end
            end
          rescue JSON::ParserError
            warnings << "Invalid JSON in #{path}"
          end
        end

        unless hooks_found
          warnings << "No hooks configured. Run 'claude-memory init' or configure manually."
          stdout.puts "\n  Manual fallback available:"
          stdout.puts "    claude-memory ingest --session-id <id> --transcript-path <path>"
          stdout.puts "    claude-memory sweep --budget 5"
          stdout.puts "    claude-memory publish"
        end
      end
    end
  end
end
