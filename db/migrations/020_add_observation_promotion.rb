# frozen_string_literal: true

# Migration v20: observation→fact promotion bridge (Phase 4 of the
# observational layer).
#
# - corroboration_count: how many times this observation has been sighted.
#   Starts at 1; the deterministic Reflector's dedup pass folds duplicates'
#   counts into the keeper instead of just dropping them. This count is the
#   "repeated sightings" signal the promotion gate requires — an observation
#   is only eligible to become a structured fact once corroborated, which
#   doubles as an anti-hallucination gate against one-off doc/example text.
# - promoted_at / promoted_fact_id: set when an observation has been promoted
#   to a fact, so it is not re-suggested. The observation row is preserved
#   (provenance), it just stops appearing as a promotion candidate.
Sequel.migration do
  up do
    alter_table(:observations) do
      add_column :corroboration_count, Integer, null: false, default: 1
      add_column :promoted_at, String       # ISO 8601, set on promotion
      add_column :promoted_fact_id, Integer  # the fact this was promoted into
    end

    run "CREATE INDEX IF NOT EXISTS idx_observations_promoted_at ON observations(promoted_at)"
  end

  down do
    alter_table(:observations) do
      drop_column :corroboration_count
      drop_column :promoted_at
      drop_column :promoted_fact_id
    end
  end
end
