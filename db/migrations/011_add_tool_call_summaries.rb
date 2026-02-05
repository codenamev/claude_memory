# frozen_string_literal: true

# Migration v11: Add compressed_summary to tool_calls
# Stores human-readable summaries of tool observations
# e.g., "Edited auth.rb: 'def login' → 'def async_login'"
Sequel.migration do
  up do
    alter_table(:tool_calls) do
      add_column :compressed_summary, String, text: true
    end
  end

  down do
    alter_table(:tool_calls) do
      drop_column :compressed_summary
    end
  end
end
