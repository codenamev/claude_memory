# frozen_string_literal: true

# Migration v7: Add ingestion metrics for ROI tracking
# - Creates ingestion_metrics table to track distillation costs
# - Tracks token usage (input/output) and facts extracted
# - Enables ROI analysis: tokens spent per fact extracted
# - Shows efficiency of memory system over time
Sequel.migration do
  up do
    create_table?(:ingestion_metrics) do
      primary_key :id
      foreign_key :content_item_id, :content_items, null: false
      Integer :input_tokens         # Tokens sent to distillation API
      Integer :output_tokens        # Tokens returned from distillation API
      Integer :facts_extracted      # Number of facts extracted from this content
      String :created_at, null: false
    end

    run "CREATE INDEX IF NOT EXISTS idx_ingestion_metrics_content_item ON ingestion_metrics(content_item_id)"
    run "CREATE INDEX IF NOT EXISTS idx_ingestion_metrics_created_at ON ingestion_metrics(created_at)"
  end

  down do
    drop_table?(:ingestion_metrics)
  end
end
