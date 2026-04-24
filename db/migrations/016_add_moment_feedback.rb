# frozen_string_literal: true

# Migration v16: Per-moment feedback (improvements.md #43).
# Tracks a single thumbs-up/down verdict (+ optional note) per activity_event
# so the dashboard can surface a trust-calibration signal. Unique on event_id
# so a given moment has at most one current verdict; repeat clicks upsert.
Sequel.migration do
  up do
    create_table?(:moment_feedback) do
      primary_key :id
      Integer :event_id, null: false
      String :verdict, null: false  # "up" | "down"
      String :note, text: true      # optional freeform note
      String :recorded_at, null: false
      index :event_id, unique: true
    end
  end

  down do
    drop_table?(:moment_feedback)
  end
end
