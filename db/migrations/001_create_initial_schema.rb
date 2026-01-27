# frozen_string_literal: true

Sequel.migration do
  up do
    create_table?(:meta) do
      String :key, primary_key: true
      String :value
    end

    # Content items store ingested transcript chunks with metadata
    # metadata_json stores extensible session metadata as JSON:
    # {
    #   "git_branch": "feature/auth",
    #   "cwd": "/path/to/project",
    #   "claude_version": "4.5",
    #   "tools_used": ["Read", "Edit", "Bash"]
    # }
    create_table?(:content_items) do
      primary_key :id
      String :source, null: false
      String :session_id
      String :transcript_path
      String :project_path
      String :occurred_at
      String :ingested_at, null: false
      String :text_hash, null: false
      Integer :byte_len, null: false
      String :raw_text, text: true
      String :metadata_json, text: true  # Extensible JSON metadata
    end

    create_table?(:delta_cursors) do
      primary_key :id
      String :session_id, null: false
      String :transcript_path, null: false
      Integer :last_byte_offset, null: false, default: 0
      String :updated_at, null: false
      unique [:session_id, :transcript_path]
    end

    create_table?(:entities) do
      primary_key :id
      String :type, null: false
      String :canonical_name, null: false
      String :slug, null: false, unique: true
      String :created_at, null: false
    end

    create_table?(:entity_aliases) do
      primary_key :id
      foreign_key :entity_id, :entities, null: false
      String :source
      String :alias, null: false
      Float :confidence, default: 1.0
    end

    create_table?(:facts) do
      primary_key :id
      foreign_key :subject_entity_id, :entities
      String :predicate, null: false
      foreign_key :object_entity_id, :entities
      String :object_literal
      String :datatype
      String :polarity, default: "positive"
      String :valid_from
      String :valid_to
      String :status, default: "active"
      Float :confidence, default: 1.0
      String :created_from
      String :created_at, null: false
      String :scope, default: "project"
      String :project_path
    end

    create_table?(:provenance) do
      primary_key :id
      foreign_key :fact_id, :facts, null: false
      foreign_key :content_item_id, :content_items
      String :quote, text: true
      foreign_key :attribution_entity_id, :entities
      String :strength, default: "stated"
    end

    create_table?(:fact_links) do
      primary_key :id
      foreign_key :from_fact_id, :facts, null: false
      foreign_key :to_fact_id, :facts, null: false
      String :link_type, null: false
    end

    create_table?(:conflicts) do
      primary_key :id
      foreign_key :fact_a_id, :facts, null: false
      foreign_key :fact_b_id, :facts, null: false
      String :status, default: "open"
      String :detected_at, null: false
      String :notes, text: true
    end

    # Indexes
    run "CREATE INDEX IF NOT EXISTS idx_facts_predicate ON facts(predicate)"
    run "CREATE INDEX IF NOT EXISTS idx_facts_subject ON facts(subject_entity_id)"
    run "CREATE INDEX IF NOT EXISTS idx_facts_status ON facts(status)"
    run "CREATE INDEX IF NOT EXISTS idx_facts_scope ON facts(scope)"
    run "CREATE INDEX IF NOT EXISTS idx_facts_project ON facts(project_path)"
    run "CREATE INDEX IF NOT EXISTS idx_provenance_fact ON provenance(fact_id)"
    run "CREATE INDEX IF NOT EXISTS idx_entity_aliases_entity ON entity_aliases(entity_id)"
    run "CREATE INDEX IF NOT EXISTS idx_content_items_session ON content_items(session_id)"
    run "CREATE INDEX IF NOT EXISTS idx_content_items_project ON content_items(project_path)"
  end

  down do
    drop_table?(:conflicts)
    drop_table?(:fact_links)
    drop_table?(:provenance)
    drop_table?(:facts)
    drop_table?(:entity_aliases)
    drop_table?(:entities)
    drop_table?(:delta_cursors)
    drop_table?(:content_items)
    drop_table?(:meta)
  end
end
