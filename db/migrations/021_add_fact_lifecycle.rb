# frozen_string_literal: true

# Migration v21: two-stage fact expiry lifecycle (#14).
#
# - reaffirmed_at: set ONLY by explicit ratification (CLI/MCP ratify
#   surface) — never by passive recall. Passive recall touches
#   last_recalled_at (v17), which self-defeats as a staleness signal:
#   frequently-recalled-but-wrong facts never age out. Ratification is the
#   distinct, intentional "still true" signal that returns an expiring
#   fact to active and resets both clocks.
# - expiring_since: set when the sweeper moves an active fact to
#   "expiring" (stale past threshold). Starts the ratification window;
#   after ratify_window_days without ratification the fact becomes
#   "expired" (excluded from default recall, never deleted, restorable).
Sequel.migration do
  up do
    alter_table(:facts) do
      add_column :reaffirmed_at, String   # ISO 8601, explicit ratification only
      add_column :expiring_since, String  # ISO 8601, entered expiring stage
    end

    run "CREATE INDEX IF NOT EXISTS idx_facts_expiring_since ON facts(expiring_since)"
  end

  down do
    alter_table(:facts) do
      drop_column :reaffirmed_at
      drop_column :expiring_since
    end
  end
end
