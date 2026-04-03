# frozen_string_literal: true

# Migration v13: Add category column to facts table.
# Decouples knowledge type (decision, convention, architecture, etc.)
# from the predicate (uses_database, naming_convention, etc.).
# LLM distillation can produce arbitrary predicates; category provides
# a stable, bounded classification for Publish, Shortcuts, and filtering.
Sequel.migration do
  up do
    alter_table(:facts) do
      add_column :category, String, text: true, default: "general"
    end

    add_index :facts, :category, if_not_exists: true

    # Backfill existing facts based on predicate patterns
    self[:facts].where(predicate: "decision").update(category: "decision")
    self[:facts].where(Sequel.like(:predicate, "decided_%")).update(category: "decision")
    self[:facts].where(predicate: "convention").update(category: "convention")
    self[:facts].where(Sequel.like(:predicate, "%_convention")).update(category: "convention")
    self[:facts].where(predicate: %w[uses_database uses_framework deployment_platform auth_method]).update(category: "architecture")
  end

  down do
    alter_table(:facts) do
      drop_column :category
    end
  end
end
