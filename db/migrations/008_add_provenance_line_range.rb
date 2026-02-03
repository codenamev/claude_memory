# frozen_string_literal: true

# Migration v8: Add line range references to provenance
# - Adds line_start and line_end columns for precise source linking
# - Enables fact verification by pointing to exact location in source content
# - 1-indexed line numbers matching standard editor conventions
Sequel.migration do
  up do
    alter_table(:provenance) do
      add_column :line_start, Integer  # 1-indexed start line in source content
      add_column :line_end, Integer    # 1-indexed end line in source content
    end
  end

  down do
    alter_table(:provenance) do
      drop_column :line_start
      drop_column :line_end
    end
  end
end
