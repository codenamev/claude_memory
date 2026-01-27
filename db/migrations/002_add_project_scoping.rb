# frozen_string_literal: true

# Migration v2: Add project scoping support
# - Adds project_path to content_items for tracking content by project
# - Adds scope (global/project) and project_path to facts
# - Adds indexes for filtering by scope and project
Sequel.migration do
  up do
    alter_table(:content_items) do
      add_column :project_path, String
    end

    alter_table(:facts) do
      add_column :scope, String, default: "project"
      add_column :project_path, String
      add_index :scope, name: :idx_facts_scope
      add_index :project_path, name: :idx_facts_project
    end
  end

  down do
    alter_table(:facts) do
      drop_index :scope, name: :idx_facts_scope
      drop_index :project_path, name: :idx_facts_project
      drop_column :scope
      drop_column :project_path
    end

    alter_table(:content_items) do
      drop_column :project_path
    end
  end
end
