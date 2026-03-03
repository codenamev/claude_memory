# frozen_string_literal: true

# Migration v12: Add vec_indexed_at tracking column to facts
# Tracks which facts have been populated in the facts_vec virtual table.
# The facts_vec virtual table itself is created lazily at runtime
# because the sqlite-vec extension must be loaded before CREATE VIRTUAL TABLE.
Sequel.migration do
  up do
    alter_table(:facts) do
      add_column :vec_indexed_at, String, text: true
    end
  end

  down do
    alter_table(:facts) do
      drop_column :vec_indexed_at
    end
  end
end
