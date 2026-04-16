# frozen_string_literal: true

# Migration v14: Canonicalize stale predicate names in existing facts.
#
# The predicate vocabulary was curated in 0.9.0 — synonym canonicalization
# now runs at insert time (Resolver), but existing facts with stale
# predicate names need a one-time rewrite so they appear in the correct
# snapshot sections and query results.
#
# This migration applies PredicatePolicy::SYNONYMS to all active facts.
# Reversible: the down migration is a no-op because we can't know the
# original predicate name after rewriting.
Sequel.migration do
  up do
    # Inline the synonym map so the migration is self-contained and
    # doesn't break if PredicatePolicy::SYNONYMS changes later.
    synonyms = {
      "has_convention" => "convention",
      "primary_language" => "uses_language"
    }

    synonyms.each do |from, to|
      self[:facts].where(predicate: from).update(predicate: to)
    end
  end

  down do
    # No-op: can't reverse a predicate rename without storing the original.
  end
end
