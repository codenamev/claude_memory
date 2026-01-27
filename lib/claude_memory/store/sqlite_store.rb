# frozen_string_literal: true

require "sequel"
require "sequel/extensions/migration"
require "json"

module ClaudeMemory
  module Store
    class SQLiteStore
      SCHEMA_VERSION = 7

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

        # Set busy timeout to 5 seconds
        # - Allows retries instead of immediate failure
        # - Critical for concurrent hook execution
        @db.run("PRAGMA busy_timeout = 5000")

        ensure_schema!
      end

      def close
        @db.disconnect
      end

      # Checkpoint the WAL file to prevent unlimited growth
      # This truncates the WAL after checkpointing
      # Should be called periodically during maintenance/sweep operations
      def checkpoint_wal
        @db.run("PRAGMA wal_checkpoint(TRUNCATE)")
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

      def ingestion_metrics
        @db[:ingestion_metrics]
      end

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

      # Record token usage metrics for a distillation operation
      #
      # @param content_item_id [Integer] The content item that was distilled
      # @param input_tokens [Integer] Tokens sent to the API
      # @param output_tokens [Integer] Tokens returned from the API
      # @param facts_extracted [Integer] Number of facts extracted
      # @return [Integer] The created metric record ID
      def record_ingestion_metrics(content_item_id:, input_tokens:, output_tokens:, facts_extracted:)
        ingestion_metrics.insert(
          content_item_id: content_item_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          facts_extracted: facts_extracted,
          created_at: Time.now.utc.iso8601
        )
      end

      # Get aggregate metrics across all distillation operations
      #
      # @return [Hash] Aggregated metrics with keys:
      #   - total_input_tokens: Total tokens sent to API
      #   - total_output_tokens: Total tokens returned from API
      #   - total_facts_extracted: Total facts extracted
      #   - total_operations: Number of distillation operations
      #   - avg_facts_per_1k_input_tokens: Average efficiency metric
      def aggregate_ingestion_metrics
        # standard:disable Performance/Detect (Sequel DSL requires .select{}.first)
        result = ingestion_metrics
          .select {
            [
              sum(:input_tokens).as(:total_input),
              sum(:output_tokens).as(:total_output),
              sum(:facts_extracted).as(:total_facts),
              count(:id).as(:total_ops)
            ]
          }
          .first
        # standard:enable Performance/Detect

        return nil if result.nil? || result[:total_ops].to_i.zero?

        total_input = result[:total_input].to_i
        total_output = result[:total_output].to_i
        total_facts = result[:total_facts].to_i
        total_ops = result[:total_ops].to_i

        efficiency = total_input.zero? ? 0.0 : (total_facts.to_f / total_input * 1000).round(2)

        {
          total_input_tokens: total_input,
          total_output_tokens: total_output,
          total_facts_extracted: total_facts,
          total_operations: total_ops,
          avg_facts_per_1k_input_tokens: efficiency
        }
      end

      private

      def ensure_schema!
        migrations_path = File.expand_path("../../../db/migrations", __dir__)

        # Handle backward compatibility: databases created with old migration system
        sync_legacy_schema_version!

        # Run Sequel migrations to bring database to target version
        Sequel::Migrator.run(@db, migrations_path, target: SCHEMA_VERSION)

        # Set created_at timestamp on first initialization
        set_meta("created_at", Time.now.utc.iso8601) unless get_meta("created_at")

        # Sync legacy schema_version meta key with Sequel's schema_info
        # This maintains backwards compatibility with code that reads schema_version
        sequel_version = @db[:schema_info].get(:version) if @db.table_exists?(:schema_info)
        set_meta("schema_version", sequel_version.to_s) if sequel_version
      end

      # Sync legacy schema_version from meta table to Sequel's schema_info
      # Handles two cases:
      # 1. No schema_info table exists (old system, pre-Sequel migrations)
      # 2. schema_info exists but is out of sync with meta.schema_version
      def sync_legacy_schema_version!
        return unless @db.table_exists?(:meta)

        meta_version = get_meta("schema_version")&.to_i
        return unless meta_version && meta_version >= 2

        # Verify database actually has v2+ schema (defensive check)
        columns = @db.schema(:content_items).map(&:first) if @db.table_exists?(:content_items)
        return unless columns&.include?(:project_path)

        # Create or update schema_info to match meta.schema_version
        @db.create_table?(:schema_info) do
          Integer :version, null: false, default: 0
        end

        sequel_version = @db[:schema_info].get(:version)
        if sequel_version.nil? || sequel_version < meta_version
          # Update schema_info to match meta (old system's version)
          @db[:schema_info].delete
          @db[:schema_info].insert(version: meta_version)
        end
      end

      def set_meta(key, value)
        @db[:meta].insert_conflict(target: :key, update: {value: value}).insert(key: key, value: value)
      end

      def get_meta(key)
        @db[:meta].where(key: key).get(:value)
      end

      def slugify(type, name)
        "#{type}:#{name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")}"
      end
    end
  end
end
