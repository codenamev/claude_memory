# frozen_string_literal: true

module ClaudeMemory
  module Infrastructure
    # Validates database schema integrity and data consistency
    # Records validation results in schema_health table
    class SchemaValidator
      EXPECTED_TABLES = %i[
        meta content_items delta_cursors entities entity_aliases facts
        provenance fact_links conflicts tool_calls
        operation_progress schema_health
      ].freeze

      # FTS table is created lazily, so it's optional
      OPTIONAL_TABLES = %i[content_fts].freeze

      CRITICAL_COLUMNS = {
        facts: %i[id subject_entity_id predicate status scope project_path embedding_json],
        content_items: %i[id source session_id text_hash ingested_at source_mtime],
        entities: %i[id type canonical_name slug],
        operation_progress: %i[id operation_type scope status started_at]
      }.freeze

      CRITICAL_INDEXES = %i[
        idx_facts_predicate idx_facts_subject idx_facts_status idx_facts_scope
        idx_facts_project idx_provenance_fact idx_content_items_session
        idx_operation_progress_type idx_operation_progress_status
      ].freeze

      def initialize(store)
        @store = store
      end

      def validate
        issues = []

        # Check tables exist
        tables = @store.db.tables
        missing_tables = EXPECTED_TABLES - tables
        missing_tables.each do |table|
          issues << {severity: "error", message: "Missing table: #{table}"}
        end

        # Check critical columns exist
        CRITICAL_COLUMNS.each do |table, columns|
          next unless tables.include?(table)

          existing_columns = @store.db.schema(table).map(&:first)
          missing_columns = columns - existing_columns
          missing_columns.each do |column|
            issues << {severity: "error", message: "Missing column #{table}.#{column}"}
          end
        end

        # Check critical indexes exist
        index_names = @store.db["SELECT name FROM sqlite_master WHERE type='index'"]
          .all.map { |r| r[:name] }
        missing_indexes = CRITICAL_INDEXES - index_names.map(&:to_sym)
        missing_indexes.each do |index|
          issues << {severity: "warning", message: "Missing index: #{index}"}
        end

        # Check for orphaned records
        check_orphaned_provenance(issues)
        check_orphaned_fact_links(issues)
        check_orphaned_tool_calls(issues)

        # Check for invalid enum values
        check_invalid_fact_scopes(issues)
        check_invalid_fact_status(issues)
        check_invalid_operation_status(issues)

        # Check embedding dimensions
        check_embedding_dimensions(issues)

        # Record validation result
        record_health_check(issues)

        {
          valid: issues.none? { |i| i[:severity] == "error" },
          issues: issues
        }
      end

      private

      def check_orphaned_provenance(issues)
        orphaned = @store.db[:provenance]
          .left_join(:facts, id: :fact_id)
          .where(Sequel[:facts][:id] => nil)
          .count

        if orphaned > 0
          issues << {severity: "error", message: "#{orphaned} orphaned provenance record(s) without corresponding facts"}
        end
      end

      def check_orphaned_fact_links(issues)
        orphaned_from = @store.db[:fact_links]
          .left_join(:facts, id: :from_fact_id)
          .where(Sequel[:facts][:id] => nil)
          .count

        orphaned_to = @store.db[:fact_links]
          .left_join(Sequel[:facts].as(:to_facts), id: :to_fact_id)
          .where(Sequel[:to_facts][:id] => nil)
          .count

        total_orphaned = orphaned_from + orphaned_to
        if total_orphaned > 0
          issues << {severity: "error", message: "#{total_orphaned} orphaned fact_links record(s)"}
        end
      end

      def check_orphaned_tool_calls(issues)
        orphaned = @store.db[:tool_calls]
          .left_join(:content_items, id: :content_item_id)
          .where(Sequel[:content_items][:id] => nil)
          .count

        if orphaned > 0
          issues << {severity: "warning", message: "#{orphaned} orphaned tool_calls record(s) without corresponding content_items"}
        end
      end

      def check_invalid_fact_scopes(issues)
        invalid = @store.facts
          .where(Sequel.~(scope: %w[global project]))
          .count

        if invalid > 0
          issues << {severity: "error", message: "#{invalid} fact(s) with invalid scope (must be 'global' or 'project')"}
        end
      end

      def check_invalid_fact_status(issues)
        valid_statuses = %w[active superseded]
        invalid = @store.facts
          .where(Sequel.~(status: valid_statuses))
          .count

        if invalid > 0
          issues << {severity: "warning", message: "#{invalid} fact(s) with non-standard status"}
        end
      end

      def check_invalid_operation_status(issues)
        return unless @store.db.tables.include?(:operation_progress)

        valid_statuses = %w[running completed failed]
        invalid = @store.operation_progress
          .where(Sequel.~(status: valid_statuses))
          .count

        if invalid > 0
          issues << {severity: "error", message: "#{invalid} operation(s) with invalid status"}
        end
      end

      def check_embedding_dimensions(issues)
        # Check that all embeddings have correct dimensions (384)
        facts_with_embeddings = @store.facts
          .where(Sequel.~(embedding_json: nil))
          .select(:id, :embedding_json)
          .limit(10)  # Sample first 10

        facts_with_embeddings.each do |fact|
          embedding = JSON.parse(fact[:embedding_json])
          if embedding.size != 384
            issues << {severity: "error", message: "Fact #{fact[:id]} has embedding with incorrect dimensions (#{embedding.size}, expected 384)"}
            break  # Only report first occurrence
          end
        end
      rescue JSON::ParserError
        issues << {severity: "error", message: "Invalid JSON in embedding_json column"}
      end

      def record_health_check(issues)
        now = Time.now.utc.iso8601
        version = @store.schema_version

        # Get table counts for snapshot
        table_counts = {}
        @store.db.tables.each do |table|
          table_counts[table.to_s] = @store.db[table].count
        end

        validation_status = if issues.any? { |i| i[:severity] == "error" }
          "corrupt"
        elsif issues.any?
          "degraded"
        else
          "healthy"
        end

        @store.schema_health.insert(
          checked_at: now,
          schema_version: version,
          validation_status: validation_status,
          issues_json: issues.to_json,
          table_counts_json: table_counts.to_json
        )
      end
    end
  end
end
