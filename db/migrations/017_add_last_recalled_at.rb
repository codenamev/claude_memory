# frozen_string_literal: true

# Migration v17: Access-based staleness scoring (improvements.md #35).
# Records the last time a fact was surfaced via memory.recall or context
# injection, derived periodically from activity_events. Sweep-derived rather
# than per-call so we avoid WAL write contention on the recall hot path.
Sequel.migration do
  up do
    add_column :facts, :last_recalled_at, String
  end

  down do
    drop_column :facts, :last_recalled_at
  end
end
