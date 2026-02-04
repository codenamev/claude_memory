# frozen_string_literal: true

# Migration v9: Add docid (short hash identifier) to facts
# - Adds docid column for user-friendly fact references (e.g., "abc123de")
# - Docids are 8-character hex strings derived from SHA256 of fact content
# - Enables cross-database references and better UX in CLI/MCP
# - Backfills existing facts with generated docids
require "digest"

Sequel.migration do
  up do
    alter_table(:facts) do
      add_column :docid, String, size: 8
    end

    run "CREATE UNIQUE INDEX IF NOT EXISTS idx_facts_docid ON facts(docid)"

    # Backfill existing facts with docids
    self[:facts].each do |fact|
      input = "#{fact[:subject_entity_id]}:#{fact[:predicate]}:#{fact[:object_literal]}:#{fact[:created_at]}"
      docid = Digest::SHA256.hexdigest(input)[0, 8]

      # Handle unlikely collisions by appending id
      existing = self[:facts].where(docid: docid).exclude(id: fact[:id]).first
      if existing
        docid = Digest::SHA256.hexdigest("#{input}:#{fact[:id]}")[0, 8]
      end

      self[:facts].where(id: fact[:id]).update(docid: docid)
    end
  end

  down do
    run "DROP INDEX IF EXISTS idx_facts_docid"
    alter_table(:facts) do
      drop_column :docid
    end
  end
end
