# frozen_string_literal: true

require "sequel"
require "json"

module ClaudeMemory
  module Store
    class SQLiteStore
      SCHEMA_VERSION = 6

      attr_reader :db

      def initialize(db_path)
        @db_path = db_path
        @db = Sequel.sqlite(db_path)

        # Enable WAL mode for better concurrency
        # - Multiple readers don't block each other
        # - Writers don't block readers
        # - Safer concurrent hook execution
        @db.run("PRAGMA journal_mode = WAL")
        @db.run("PRAGMA synchronous = NORMAL")

        ensure_schema!
      end

      def close
        @db.disconnect
      end

      def schema_version
        @db[:meta].where(key: "schema_version").get(:value)&.to_i
      end

      def content_items
        @db[:content_items]
      end

      def delta_cursors
        @db[:delta_cursors]
      end

      def entities
        @db[:entities]
      end

      def entity_aliases
        @db[:entity_aliases]
      end

      def facts
        @db[:facts]
      end

      def provenance
        @db[:provenance]
      end

      def fact_links
        @db[:fact_links]
      end

      def conflicts
        @db[:conflicts]
      end

      def tool_calls
        @db[:tool_calls]
      end

      def operation_progress
        @db[:operation_progress]
      end

      def schema_health
        @db[:schema_health]
      end

      private

      def ensure_schema!
        create_tables!
        set_meta("created_at", Time.now.utc.iso8601) unless get_meta("created_at")
        run_migrations_safely!
      end

      def run_migrations_safely!
        current = get_meta("schema_version")&.to_i || 0

        migrate_to_v2_safe! if current < 2
        migrate_to_v3_safe! if current < 3
        migrate_to_v4_safe! if current < 4
        migrate_to_v5_safe! if current < 5
        migrate_to_v6_safe! if current < 6
      end

      def migrate_to_v2_safe!
        @db.transaction do
          columns = @db.schema(:content_items).map(&:first)
          unless columns.include?(:project_path)
            @db.alter_table(:content_items) do
              add_column :project_path, String
            end
          end

          columns = @db.schema(:facts).map(&:first)
          unless columns.include?(:scope)
            @db.alter_table(:facts) do
              add_column :scope, String, default: "project"
              add_column :project_path, String
              add_index :scope, name: :idx_facts_scope
              add_index :project_path, name: :idx_facts_project
            end
          end

          # Update version INSIDE transaction for atomicity
          set_meta("schema_version", "2")
        end
      rescue => e
        raise StandardError, "Migration to v2 failed: #{e.message}"
      end

      def migrate_to_v3_safe!
        @db.transaction do
          # Add session metadata columns to content_items
          columns = @db.schema(:content_items).map(&:first)
          unless columns.include?(:git_branch)
            @db.alter_table(:content_items) do
              add_column :git_branch, String
              add_column :cwd, String
              add_column :claude_version, String
              add_column :thinking_level, String
            end
          end

          # Add index for filtering by branch
          create_index_if_not_exists(:content_items, :git_branch, :idx_content_items_git_branch)

          # Create tool_calls table for tracking tool usage
          @db.create_table?(:tool_calls) do
            primary_key :id
            foreign_key :content_item_id, :content_items, on_delete: :cascade
            String :tool_name, null: false
            String :tool_input, text: true  # JSON of input parameters
            String :tool_result, text: true  # Truncated result (first 500 chars)
            TrueClass :is_error, default: false
            String :timestamp, null: false
          end

          create_index_if_not_exists(:tool_calls, :tool_name, :idx_tool_calls_tool_name)
          create_index_if_not_exists(:tool_calls, :content_item_id, :idx_tool_calls_content_item)

          # Update version INSIDE transaction for atomicity
          set_meta("schema_version", "3")
        end
      rescue => e
        raise StandardError, "Migration to v3 failed: #{e.message}"
      end

      def migrate_to_v4_safe!
        @db.transaction do
          # Add embeddings column to facts for semantic search
          columns = @db.schema(:facts).map(&:first)
          unless columns.include?(:embedding_json)
            @db.alter_table(:facts) do
              add_column :embedding_json, String, text: true  # JSON array of floats
            end
          end

          # Note: We use JSON storage for embeddings instead of sqlite-vec extension
          # Similarity calculations are done in Ruby using cosine similarity
          # Future: Could migrate to native vector extension or external vector DB

          # Update version INSIDE transaction for atomicity
          set_meta("schema_version", "4")
        end
      rescue => e
        raise StandardError, "Migration to v4 failed: #{e.message}"
      end

      def migrate_to_v5_safe!
        @db.transaction do
          # Add source_mtime for incremental sync
          columns = @db.schema(:content_items).map(&:first)
          unless columns.include?(:source_mtime)
            @db.alter_table(:content_items) do
              add_column :source_mtime, String  # ISO8601 timestamp of source file mtime
            end
          end

          # Index for efficient mtime lookups
          create_index_if_not_exists(:content_items, :source_mtime, :idx_content_items_source_mtime)

          # Update version INSIDE transaction for atomicity
          set_meta("schema_version", "5")
        end
      rescue => e
        raise StandardError, "Migration to v5 failed: #{e.message}"
      end

      def migrate_to_v6_safe!
        @db.transaction do
          # Create operation_progress table for tracking long-running operations
          @db.create_table?(:operation_progress) do
            primary_key :id
            String :operation_type, null: false  # "index_embeddings", "sweep", "distill"
            String :scope, null: false           # "global" or "project"
            String :status, null: false          # "running", "completed", "failed"
            Integer :total_items
            Integer :processed_items, default: 0
            String :checkpoint_data, text: true  # JSON for resumption
            String :started_at, null: false
            String :completed_at
          end

          create_index_if_not_exists(:operation_progress, :operation_type, :idx_operation_progress_type)
          create_index_if_not_exists(:operation_progress, :status, :idx_operation_progress_status)

          # Create schema_health table for validation results
          @db.create_table?(:schema_health) do
            primary_key :id
            String :checked_at, null: false
            Integer :schema_version, null: false
            String :validation_status, null: false  # "healthy", "corrupt", "unknown"
            String :issues_json, text: true         # Array of detected problems
            String :table_counts_json, text: true   # Snapshot of table row counts
          end

          create_index_if_not_exists(:schema_health, :checked_at, :idx_schema_health_checked_at)

          # Update version INSIDE transaction for atomicity
          set_meta("schema_version", "6")
        end
      rescue => e
        raise StandardError, "Migration to v6 failed: #{e.message}"
      end

      def create_tables!
        @db.create_table?(:meta) do
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
        @db.create_table?(:content_items) do
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

        @db.create_table?(:delta_cursors) do
          primary_key :id
          String :session_id, null: false
          String :transcript_path, null: false
          Integer :last_byte_offset, null: false, default: 0
          String :updated_at, null: false
          unique [:session_id, :transcript_path]
        end

        @db.create_table?(:entities) do
          primary_key :id
          String :type, null: false
          String :canonical_name, null: false
          String :slug, null: false, unique: true
          String :created_at, null: false
        end

        @db.create_table?(:entity_aliases) do
          primary_key :id
          foreign_key :entity_id, :entities, null: false
          String :source
          String :alias, null: false
          Float :confidence, default: 1.0
        end

        @db.create_table?(:facts) do
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

        @db.create_table?(:provenance) do
          primary_key :id
          foreign_key :fact_id, :facts, null: false
          foreign_key :content_item_id, :content_items
          String :quote, text: true
          foreign_key :attribution_entity_id, :entities
          String :strength, default: "stated"
        end

        @db.create_table?(:fact_links) do
          primary_key :id
          foreign_key :from_fact_id, :facts, null: false
          foreign_key :to_fact_id, :facts, null: false
          String :link_type, null: false
        end

        @db.create_table?(:conflicts) do
          primary_key :id
          foreign_key :fact_a_id, :facts, null: false
          foreign_key :fact_b_id, :facts, null: false
          String :status, default: "open"
          String :detected_at, null: false
          String :notes, text: true
        end

        create_index_if_not_exists(:facts, :predicate, :idx_facts_predicate)
        create_index_if_not_exists(:facts, :subject_entity_id, :idx_facts_subject)
        create_index_if_not_exists(:facts, :status, :idx_facts_status)
        create_index_if_not_exists(:facts, :scope, :idx_facts_scope)
        create_index_if_not_exists(:facts, :project_path, :idx_facts_project)
        create_index_if_not_exists(:provenance, :fact_id, :idx_provenance_fact)
        create_index_if_not_exists(:entity_aliases, :entity_id, :idx_entity_aliases_entity)
        create_index_if_not_exists(:content_items, :session_id, :idx_content_items_session)
        create_index_if_not_exists(:content_items, :project_path, :idx_content_items_project)
      end

      def create_index_if_not_exists(table, column, name)
        @db.run("CREATE INDEX IF NOT EXISTS #{name} ON #{table}(#{column})")
      end

      def set_meta(key, value)
        @db[:meta].insert_conflict(target: :key, update: {value: value}).insert(key: key, value: value)
      end

      def get_meta(key)
        @db[:meta].where(key: key).get(:value)
      end

      public

      def upsert_content_item(source:, text_hash:, byte_len:, session_id: nil, transcript_path: nil,
        project_path: nil, occurred_at: nil, raw_text: nil, metadata: nil,
        git_branch: nil, cwd: nil, claude_version: nil, thinking_level: nil, source_mtime: nil)
        existing = content_items.where(text_hash: text_hash, session_id: session_id).get(:id)
        return existing if existing

        now = Time.now.utc.iso8601
        content_items.insert(
          source: source,
          session_id: session_id,
          transcript_path: transcript_path,
          project_path: project_path,
          occurred_at: occurred_at || now,
          ingested_at: now,
          text_hash: text_hash,
          byte_len: byte_len,
          raw_text: raw_text,
          metadata_json: metadata&.to_json,
          git_branch: git_branch,
          cwd: cwd,
          claude_version: claude_version,
          thinking_level: thinking_level,
          source_mtime: source_mtime
        )
      end

      def content_item_by_transcript_and_mtime(transcript_path, mtime_iso8601)
        content_items
          .where(transcript_path: transcript_path, source_mtime: mtime_iso8601)
          .first
      end

      def insert_tool_calls(content_item_id, tool_calls_data)
        tool_calls_data.each do |tc|
          tool_calls.insert(
            content_item_id: content_item_id,
            tool_name: tc[:tool_name],
            tool_input: tc[:tool_input],
            tool_result: tc[:tool_result],
            is_error: tc[:is_error] || false,
            timestamp: tc[:timestamp]
          )
        end
      end

      def tool_calls_for_content_item(content_item_id)
        tool_calls
          .where(content_item_id: content_item_id)
          .order(:timestamp)
          .all
      end

      def get_delta_cursor(session_id, transcript_path)
        delta_cursors.where(session_id: session_id, transcript_path: transcript_path).get(:last_byte_offset)
      end

      def update_delta_cursor(session_id, transcript_path, offset)
        now = Time.now.utc.iso8601
        delta_cursors
          .insert_conflict(
            target: [:session_id, :transcript_path],
            update: {last_byte_offset: offset, updated_at: now}
          )
          .insert(
            session_id: session_id,
            transcript_path: transcript_path,
            last_byte_offset: offset,
            updated_at: now
          )
      end

      def find_or_create_entity(type:, name:)
        slug = slugify(type, name)
        existing = entities.where(slug: slug).get(:id)
        return existing if existing

        now = Time.now.utc.iso8601
        entities.insert(type: type, canonical_name: name, slug: slug, created_at: now)
      end

      def insert_fact(subject_entity_id:, predicate:, object_entity_id: nil, object_literal: nil,
        datatype: nil, polarity: "positive", valid_from: nil, status: "active",
        confidence: 1.0, created_from: nil, scope: "project", project_path: nil)
        now = Time.now.utc.iso8601
        facts.insert(
          subject_entity_id: subject_entity_id,
          predicate: predicate,
          object_entity_id: object_entity_id,
          object_literal: object_literal,
          datatype: datatype,
          polarity: polarity,
          valid_from: valid_from || now,
          status: status,
          confidence: confidence,
          created_from: created_from,
          created_at: now,
          scope: scope,
          project_path: project_path
        )
      end

      def update_fact(fact_id, status: nil, valid_to: nil, scope: nil, project_path: nil, embedding: nil)
        updates = {}
        updates[:status] = status if status
        updates[:valid_to] = valid_to if valid_to

        if scope
          updates[:scope] = scope
          updates[:project_path] = (scope == "global") ? nil : project_path
        end

        if embedding
          updates[:embedding_json] = embedding.to_json
        end

        return false if updates.empty?

        facts.where(id: fact_id).update(updates)
        true
      end

      def update_fact_embedding(fact_id, embedding_vector)
        facts.where(id: fact_id).update(embedding_json: embedding_vector.to_json)
      end

      def facts_with_embeddings(limit: 1000)
        facts
          .where(Sequel.~(embedding_json: nil))
          .where(status: "active")
          .select(:id, :subject_entity_id, :predicate, :object_literal, :embedding_json, :scope)
          .limit(limit)
          .all
      end

      def facts_for_slot(subject_entity_id, predicate, status: "active")
        facts
          .where(subject_entity_id: subject_entity_id, predicate: predicate, status: status)
          .select(:id, :subject_entity_id, :predicate, :object_entity_id, :object_literal,
            :datatype, :polarity, :valid_from, :valid_to, :status, :confidence,
            :created_from, :created_at)
          .all
      end

      def insert_provenance(fact_id:, content_item_id: nil, quote: nil, attribution_entity_id: nil, strength: "stated")
        provenance.insert(
          fact_id: fact_id,
          content_item_id: content_item_id,
          quote: quote,
          attribution_entity_id: attribution_entity_id,
          strength: strength
        )
      end

      def provenance_for_fact(fact_id)
        provenance.where(fact_id: fact_id).all
      end

      def insert_conflict(fact_a_id:, fact_b_id:, status: "open", notes: nil)
        now = Time.now.utc.iso8601
        conflicts.insert(
          fact_a_id: fact_a_id,
          fact_b_id: fact_b_id,
          status: status,
          detected_at: now,
          notes: notes
        )
      end

      def open_conflicts
        conflicts.where(status: "open").all
      end

      def insert_fact_link(from_fact_id:, to_fact_id:, link_type:)
        fact_links.insert(from_fact_id: from_fact_id, to_fact_id: to_fact_id, link_type: link_type)
      end

      private

      def slugify(type, name)
        "#{type}:#{name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")}"
      end
    end
  end
end
