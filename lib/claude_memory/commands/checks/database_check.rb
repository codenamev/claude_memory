# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Checks database existence, schema, and health
      class DatabaseCheck
        def initialize(db_path, label)
          @db_path = db_path
          @label = label
        end

        def call
          unless File.exist?(@db_path)
            return missing_database_result
          end

          check_database_health
        rescue => e
          {
            status: :error,
            label: @label,
            message: "#{@label} database error: #{e.message}",
            details: {}
          }
        end

        private

        def missing_database_result
          if @label == "global"
            {
              status: :error,
              label: @label,
              message: "Global database not found: #{@db_path}",
              details: {}
            }
          else
            {
              status: :warning,
              label: @label,
              message: "Project database not found: #{@db_path} (run 'claude-memory init')",
              details: {}
            }
          end
        end

        def check_database_health
          store = ClaudeMemory::Store::SQLiteStore.new(@db_path)

          details = {
            path: @db_path,
            adapter: "extralite",
            schema_version: store.schema_version,
            fact_count: store.facts.count,
            content_count: store.content_items.count,
            conflict_count: store.conflicts.where(status: "open").count,
            last_ingest: store.content_items.max(:ingested_at)
          }

          warnings = []
          errors = []

          # Check for open conflicts
          if details[:conflict_count] > 0
            warnings << "#{details[:conflict_count]} open conflict(s) need resolution"
          end

          # Check for missing ingests
          if details[:last_ingest].nil? && @label == "project"
            warnings << "No content has been ingested yet"
          end

          # Check for stuck operations
          tracker = ClaudeMemory::Infrastructure::OperationTracker.new(store)
          stuck_ops = tracker.stuck_operations
          if stuck_ops.any?
            stuck_ops.each do |op|
              warnings << "Stuck operation '#{op[:operation_type]}' (started #{op[:started_at]}). Run 'claude-memory recover' to reset."
            end
          end
          details[:stuck_operations] = stuck_ops.size

          # Run schema validation
          validator = ClaudeMemory::Infrastructure::SchemaValidator.new(store)
          validation = validator.validate
          details[:schema_valid] = validation[:valid]

          # Collect validation issues
          if validation[:issues].any?
            validation[:issues].each do |issue|
              if issue[:severity] == "error"
                errors << issue[:message]
              else
                warnings << issue[:message]
              end
            end
          end

          store.close

          status = if errors.any?
            :error
          else
            (warnings.any? ? :warning : :ok)
          end

          {
            status: status,
            label: @label,
            message: "#{@label.capitalize} database exists: #{@db_path}",
            details: details,
            warnings: warnings,
            errors: errors
          }
        end
      end
    end
  end
end
