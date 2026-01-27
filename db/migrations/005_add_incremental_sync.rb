# frozen_string_literal: true

# Migration v5: Add incremental sync support
# - Adds source_mtime to content_items for tracking file modification times
# - Enables efficient incremental sync: only re-ingest when source changed
# - Index for efficient mtime-based lookups
Sequel.migration do
  up do
    alter_table(:content_items) do
      add_column :source_mtime, String  # ISO8601 timestamp of source file mtime
      add_index :source_mtime, name: :idx_content_items_source_mtime
    end
  end

  down do
    alter_table(:content_items) do
      drop_index :source_mtime, name: :idx_content_items_source_mtime
      drop_column :source_mtime
    end
  end
end
