# frozen_string_literal: true

# Migration v22: cascade ingestion_metrics when its content item is deleted.
#
# ingestion_metrics.content_item_id was created (v7) as a plain
# `foreign_key ..., null: false` with no ON DELETE action, unlike its
# sibling tool_calls which cascades. Sweep::Maintenance#prune_old_content
# deletes aged content items that carry no provenance, and any such item
# that still has a metrics row raises ForeignKeyConstraintViolation. The
# raise escapes the sweeper, so a single aged row aborts the whole sweep
# and no pruning ever runs — databases grow without bound.
#
# SQLite cannot alter a foreign key in place, so rebuild the table.
Sequel.migration do
  up do
    # Drop rows whose content item is already gone; they would block the
    # copy into a table that enforces the reference.
    run <<~SQL
      DELETE FROM ingestion_metrics
      WHERE content_item_id NOT IN (SELECT id FROM content_items)
    SQL

    create_table(:ingestion_metrics_new) do
      primary_key :id
      foreign_key :content_item_id, :content_items, null: false, on_delete: :cascade
      Integer :input_tokens
      Integer :output_tokens
      Integer :facts_extracted
      String :created_at, null: false
    end

    run <<~SQL
      INSERT INTO ingestion_metrics_new
        (id, content_item_id, input_tokens, output_tokens, facts_extracted, created_at)
      SELECT id, content_item_id, input_tokens, output_tokens, facts_extracted, created_at
      FROM ingestion_metrics
    SQL

    drop_table(:ingestion_metrics)
    rename_table(:ingestion_metrics_new, :ingestion_metrics)

    run "CREATE INDEX IF NOT EXISTS idx_ingestion_metrics_content_item ON ingestion_metrics(content_item_id)"
    run "CREATE INDEX IF NOT EXISTS idx_ingestion_metrics_created_at ON ingestion_metrics(created_at)"
  end

  down do
    create_table(:ingestion_metrics_old) do
      primary_key :id
      foreign_key :content_item_id, :content_items, null: false
      Integer :input_tokens
      Integer :output_tokens
      Integer :facts_extracted
      String :created_at, null: false
    end

    run <<~SQL
      INSERT INTO ingestion_metrics_old
        (id, content_item_id, input_tokens, output_tokens, facts_extracted, created_at)
      SELECT id, content_item_id, input_tokens, output_tokens, facts_extracted, created_at
      FROM ingestion_metrics
    SQL

    drop_table(:ingestion_metrics)
    rename_table(:ingestion_metrics_old, :ingestion_metrics)

    run "CREATE INDEX IF NOT EXISTS idx_ingestion_metrics_content_item ON ingestion_metrics(content_item_id)"
    run "CREATE INDEX IF NOT EXISTS idx_ingestion_metrics_created_at ON ingestion_metrics(created_at)"
  end
end
