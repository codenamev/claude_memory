# frozen_string_literal: true

# Migration v19: Add observations table — the episodic memory layer.
#
# Facts answer "what is true" (semantic memory); observations answer "what
# happened" (episodic memory). This is the storage half of Phase 1 of the
# observational layer (see docs/influence/mastra-observational-memory.md).
#
# Observations are append-only: the Reflector consolidates by writing a new
# observation and pointing superseded ones at it via consolidated_into,
# rather than hard-deleting — preserving provenance (unlike Mastra's lossy
# drop). source_content_item_id links each observation back to the raw
# transcript chunk it was distilled from.
Sequel.migration do
  up do
    create_table?(:observations) do
      primary_key :id
      String :body, text: true, null: false        # dense narrative text — the observation itself
      String :kind, null: false, default: "event"  # user_statement | agent_action | tool_result | preference | decision | event
      Integer :priority, null: false, default: 3    # 1=important (🔴), 2=maybe (🟡), 3=info (🟢)
      String :scope, null: false, default: "project" # "project" or "global"
      String :project_path                          # set for project-scoped observations
      Integer :source_content_item_id               # provenance: raw transcript chunk
      Integer :consolidated_into                    # Reflector lineage: id of the observation this was merged into
      Integer :token_count                          # for budget / compression math (Phase 2)
      String :status, null: false, default: "active" # "active" or "consolidated"
      String :session_id                            # session that produced the observation
      String :observed_at, null: false              # ISO 8601 event time
      String :created_at, null: false               # ISO 8601 row creation time
      String :reflected_at                          # ISO 8601 — set when the Reflector last touched it
    end

    run "CREATE INDEX IF NOT EXISTS idx_observations_status ON observations(status)"
    run "CREATE INDEX IF NOT EXISTS idx_observations_scope ON observations(scope)"
    run "CREATE INDEX IF NOT EXISTS idx_observations_observed_at ON observations(observed_at)"
    run "CREATE INDEX IF NOT EXISTS idx_observations_source ON observations(source_content_item_id)"
    run "CREATE INDEX IF NOT EXISTS idx_observations_consolidated_into ON observations(consolidated_into)"
  end

  down do
    drop_table?(:observations)
  end
end
