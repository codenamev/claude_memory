# frozen_string_literal: true

require "sequel"
require "sequel/extensions/migration"
require "digest"
require "json"
require "extralite"
require "sequel/adapters/extralite"
require_relative "retry_handler"
require_relative "schema_manager"

module ClaudeMemory
  module Store
    class SQLiteStore
      include RetryHandler
      include SchemaManager

      attr_reader :db

      def initialize(db_path)
        @db_path = db_path
        @db = connect_database(db_path)

        ensure_schema!
      end

      def close
        @db.disconnect
      end

      def vector_index
        @vector_index ||= Index::VectorIndex.new(self)
      end

      # Checkpoint the WAL file to prevent unlimited growth
      def checkpoint_wal
        @db.run("PRAGMA wal_checkpoint(TRUNCATE)")
      end

      def schema_version
        @db[:meta].where(key: "schema_version").get(:value)&.to_i
      end

      # --- Table accessors ---

      def content_items = @db[:content_items]

      def delta_cursors = @db[:delta_cursors]

      def entities = @db[:entities]

      def entity_aliases = @db[:entity_aliases]

      def facts = @db[:facts]

      def provenance = @db[:provenance]

      def fact_links = @db[:fact_links]

      def conflicts = @db[:conflicts]

      def tool_calls = @db[:tool_calls]

      def operation_progress = @db[:operation_progress]

      def schema_health = @db[:schema_health]

      def ingestion_metrics = @db[:ingestion_metrics]

      def llm_cache = @db[:llm_cache]

      def mcp_tool_calls = @db[:mcp_tool_calls]

      # Record a single MCP tool invocation for telemetry.
      # Inserts synchronously; callers wrap in with_retry at the call site
      # if needed. Called_at defaults to now in UTC ISO8601.
      def insert_mcp_tool_call(tool_name:, duration_ms:, result_count: nil, scope: nil, error_class: nil, called_at: nil)
        mcp_tool_calls.insert(
          tool_name: tool_name,
          called_at: called_at || Time.now.utc.iso8601,
          duration_ms: duration_ms,
          result_count: result_count,
          scope: scope,
          error_class: error_class
        )
      end

      # --- Content items ---

      def upsert_content_item(source:, text_hash:, byte_len:, session_id: nil, transcript_path: nil,
        project_path: nil, occurred_at: nil, raw_text: nil, metadata: nil,
        git_branch: nil, cwd: nil, claude_version: nil, thinking_level: nil, source_mtime: nil)
        with_retry("upsert_content_item") do
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
      end

      def get_content_item(id)
        content_items.where(id: id).first
      end

      def content_item_by_transcript_and_mtime(transcript_path, mtime_iso8601)
        content_items
          .where(transcript_path: transcript_path, source_mtime: mtime_iso8601)
          .first
      end

      # --- Tool calls ---

      def insert_tool_calls(content_item_id, tool_calls_data)
        tool_calls_data.each do |tc|
          tool_calls.insert(
            content_item_id: content_item_id,
            tool_name: tc[:tool_name],
            tool_input: tc[:tool_input],
            tool_result: tc[:tool_result],
            compressed_summary: tc[:compressed_summary],
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

      # --- Delta cursors ---

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

      # --- Entities ---

      def find_or_create_entity(type:, name:)
        slug = slugify(type, name)
        existing = entities.where(slug: slug).get(:id)
        return existing if existing

        now = Time.now.utc.iso8601
        entities.insert(type: type, canonical_name: name, slug: slug, created_at: now)
      end

      # --- Facts ---

      def insert_fact(subject_entity_id:, predicate:, object_entity_id: nil, object_literal: nil,
        datatype: nil, polarity: "positive", valid_from: nil, status: "active",
        confidence: 1.0, created_from: nil, scope: "project", project_path: nil)
        now = Time.now.utc.iso8601
        docid = generate_docid(subject_entity_id, predicate, object_literal, now)
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
          project_path: project_path,
          docid: docid
        )
      end

      def find_fact_by_docid(docid)
        facts.where(docid: docid).first
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

      # Reject a fact as incorrect (e.g. a distiller hallucination).
      # Sets status to "rejected", closes any open conflicts involving
      # the fact, and records the reason in conflict notes when provided.
      # All updates run in a single transaction.
      #
      # @return [Hash, nil] {rejected: bool, conflicts_resolved: Integer}
      #   or nil if the fact does not exist.
      def reject_fact(fact_id, reason: nil)
        row = facts.where(id: fact_id).first
        return nil unless row

        now = Time.now.utc.iso8601
        resolved = 0

        @db.transaction do
          facts.where(id: fact_id).update(status: "rejected", valid_to: now)

          open_conflict_rows = conflicts
            .where(status: "open")
            .where { (fact_a_id =~ fact_id) | (fact_b_id =~ fact_id) }
            .all

          open_conflict_rows.each do |conflict|
            suffix = reason ? " | resolved: rejected fact #{fact_id} (#{reason})" : " | resolved: rejected fact #{fact_id}"
            notes = "#{conflict[:notes]}#{suffix}"
            conflicts.where(id: conflict[:id]).update(status: "resolved", notes: notes)
          end
          resolved = open_conflict_rows.size
        end

        {rejected: true, conflicts_resolved: resolved}
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

      # --- Provenance ---

      def insert_provenance(fact_id:, content_item_id: nil, quote: nil, attribution_entity_id: nil, strength: "stated",
        line_start: nil, line_end: nil)
        provenance.insert(
          fact_id: fact_id,
          content_item_id: content_item_id,
          quote: quote,
          attribution_entity_id: attribution_entity_id,
          strength: strength,
          line_start: line_start,
          line_end: line_end
        )
      end

      def provenance_for_fact(fact_id)
        provenance.where(fact_id: fact_id).all
      end

      # --- Conflicts & fact links ---

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

      # --- Ingestion metrics ---

      def undistilled_content_items(limit: 3, min_length: 200)
        content_items
          .left_join(:ingestion_metrics, content_item_id: :id)
          .where(Sequel[:ingestion_metrics][:id] => nil)
          .where { byte_len >= min_length }
          .order(Sequel.desc(:occurred_at))
          .limit(limit)
          .select_all(:content_items)
          .all
      end

      def count_undistilled(min_length: 200)
        content_items
          .left_join(:ingestion_metrics, content_item_id: :id)
          .where(Sequel[:ingestion_metrics][:id] => nil)
          .where { byte_len >= min_length }
          .count
      end

      def record_ingestion_metrics(content_item_id:, input_tokens:, output_tokens:, facts_extracted:)
        ingestion_metrics.insert(
          content_item_id: content_item_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          facts_extracted: facts_extracted,
          created_at: Time.now.utc.iso8601
        )
      end

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

      def backfill_distillation_metrics!
        undistilled_ids = content_items
          .left_join(:ingestion_metrics, content_item_id: :id)
          .where(Sequel[:ingestion_metrics][:id] => nil)
          .select_map(Sequel[:content_items][:id])

        return 0 if undistilled_ids.empty?

        now = Time.now.utc.iso8601
        undistilled_ids.each do |cid|
          ingestion_metrics.insert(
            content_item_id: cid,
            input_tokens: 0,
            output_tokens: 0,
            facts_extracted: 0,
            created_at: now
          )
        end

        undistilled_ids.size
      end

      # --- LLM cache ---

      def llm_cache_lookup(cache_key)
        llm_cache.where(cache_key: cache_key).first
      end

      def llm_cache_store(operation:, model:, input_hash:, result_json:, input_tokens: nil, output_tokens: nil)
        cache_key = Digest::SHA256.hexdigest("#{operation}:#{model}:#{input_hash}")

        llm_cache
          .insert_conflict(target: :cache_key, update: {
            result_json: result_json,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            created_at: Time.now.utc.iso8601
          })
          .insert(
            cache_key: cache_key,
            operation: operation,
            model: model,
            input_hash: input_hash,
            result_json: result_json,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            created_at: Time.now.utc.iso8601
          )
      end

      def llm_cache_key(operation, model, input)
        input_hash = Digest::SHA256.hexdigest(input)
        Digest::SHA256.hexdigest("#{operation}:#{model}:#{input_hash}")
      end

      def llm_cache_prune(max_age_seconds: 604_800)
        cutoff = (Time.now - max_age_seconds).utc.iso8601
        llm_cache.where { created_at < cutoff }.delete
      end

      # --- Meta ---

      def set_meta(key, value)
        @db[:meta].insert_conflict(target: :key, update: {value: value}).insert(key: key, value: value)
      end

      def get_meta(key)
        @db[:meta].where(key: key).get(:value)
      end

      private

      def generate_docid(subject_entity_id, predicate, object_literal, created_at)
        input = "#{subject_entity_id}:#{predicate}:#{object_literal}:#{created_at}"
        docid = Digest::SHA256.hexdigest(input)[0, 8]

        counter = 0
        while facts.where(docid: docid).any?
          counter += 1
          docid = Digest::SHA256.hexdigest("#{input}:#{counter}")[0, 8]
        end

        docid
      end

      def slugify(type, name)
        "#{type}:#{name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")}"
      end
    end
  end
end
