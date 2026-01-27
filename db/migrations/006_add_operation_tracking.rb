# frozen_string_literal: true

# Migration v6: Add operation tracking and schema health monitoring
# - Creates operation_progress table for long-running operations
# - Creates schema_health table for validation and corruption detection
# - Enables resumable operations with checkpoint support
Sequel.migration do
  up do
    create_table?(:operation_progress) do
      primary_key :id
      String :operation_type, null: false  # "index_embeddings", "sweep", "distill"
      String :scope, null: false           # "global" or "project"
      String :status, null: false          # "running", "completed", "failed"
      Integer :total_items
      Integer :processed_items, default: 0
      String :checkpoint_data, text: true  # JSON for resumption
      String :started_at, null: false
      String :completed_at
    end

    run "CREATE INDEX IF NOT EXISTS idx_operation_progress_type ON operation_progress(operation_type)"
    run "CREATE INDEX IF NOT EXISTS idx_operation_progress_status ON operation_progress(status)"

    create_table?(:schema_health) do
      primary_key :id
      String :checked_at, null: false
      Integer :schema_version, null: false
      String :validation_status, null: false  # "healthy", "corrupt", "unknown"
      String :issues_json, text: true         # Array of detected problems
      String :table_counts_json, text: true   # Snapshot of table row counts
    end

    run "CREATE INDEX IF NOT EXISTS idx_schema_health_checked_at ON schema_health(checked_at)"
  end

  down do
    drop_table?(:operation_progress)
    drop_table?(:schema_health)
  end
end
