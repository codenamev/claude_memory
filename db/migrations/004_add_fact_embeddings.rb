# frozen_string_literal: true

# Migration v4: Add embeddings for semantic search
# - Adds embedding_json column to facts table for vector storage
# - Uses JSON storage for embeddings instead of sqlite-vec extension
# - Similarity calculations are done in Ruby using cosine similarity
# - Future: Could migrate to native vector extension or external vector DB
Sequel.migration do
  up do
    alter_table(:facts) do
      add_column :embedding_json, String, text: true  # JSON array of floats
    end
  end

  down do
    alter_table(:facts) do
      drop_column :embedding_json
    end
  end
end
