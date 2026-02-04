# frozen_string_literal: true

# Migration v10: Add LLM response cache for distillation cost reduction
# - Creates llm_cache table to cache API responses by content hash
# - Cache key: SHA256(operation + model + input)
# - Enables significant cost savings for repeated/similar distillation requests
# - Includes TTL support via created_at for future cache expiration
Sequel.migration do
  up do
    create_table?(:llm_cache) do
      primary_key :id
      String :cache_key, null: false, unique: true  # SHA256 hex digest
      String :operation, null: false                 # e.g., "distill", "extract"
      String :model, null: false                     # e.g., "claude-sonnet-4-20250514"
      String :input_hash, null: false                # SHA256 of input content
      String :result_json, text: true, null: false   # Cached JSON response
      Integer :input_tokens                          # Tokens in request
      Integer :output_tokens                         # Tokens in response
      String :created_at, null: false
    end

    run "CREATE INDEX IF NOT EXISTS idx_llm_cache_key ON llm_cache(cache_key)"
    run "CREATE INDEX IF NOT EXISTS idx_llm_cache_created_at ON llm_cache(created_at)"
    run "CREATE INDEX IF NOT EXISTS idx_llm_cache_operation ON llm_cache(operation)"
  end

  down do
    drop_table?(:llm_cache)
  end
end
