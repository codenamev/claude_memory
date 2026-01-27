# frozen_string_literal: true

# Migration v3: Add session metadata and tool tracking
# - Adds git_branch, cwd, claude_version, thinking_level to content_items
# - Creates tool_calls table for tracking tool usage per content item
# - Adds indexes for efficient querying
Sequel.migration do
  up do
    alter_table(:content_items) do
      add_column :git_branch, String
      add_column :cwd, String
      add_column :claude_version, String
      add_column :thinking_level, String
      add_index :git_branch, name: :idx_content_items_git_branch
    end

    create_table?(:tool_calls) do
      primary_key :id
      foreign_key :content_item_id, :content_items, on_delete: :cascade
      String :tool_name, null: false
      String :tool_input, text: true  # JSON of input parameters
      String :tool_result, text: true  # Truncated result (first 500 chars)
      TrueClass :is_error, default: false
      String :timestamp, null: false
    end

    run "CREATE INDEX IF NOT EXISTS idx_tool_calls_tool_name ON tool_calls(tool_name)"
    run "CREATE INDEX IF NOT EXISTS idx_tool_calls_content_item ON tool_calls(content_item_id)"
  end

  down do
    alter_table(:content_items) do
      drop_index :git_branch, name: :idx_content_items_git_branch
      drop_column :git_branch
      drop_column :cwd
      drop_column :claude_version
      drop_column :thinking_level
    end

    drop_table?(:tool_calls)
  end
end
