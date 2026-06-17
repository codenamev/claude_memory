# frozen_string_literal: true

require "sequel"
require "sequel/extensions/migration"
require "digest"
require "json"
require "extralite"
require "sequel/adapters/extralite"
require_relative "retry_handler"
require_relative "schema_manager"
require_relative "llm_cache"
require_relative "metrics_aggregator"

module ClaudeMemory
  module Store
    # SQLite-backed fact store for ClaudeMemory.
    # Manages all database tables (content_items, entities, facts, provenance,
    # conflicts, fact_links, etc.) via Sequel with Extralite adapter.
    # Includes RetryHandler for transient lock recovery and SchemaManager
    # for automatic migrations on open.
    class SQLiteStore
      include RetryHandler
      include SchemaManager
      include LLMCache
      include MetricsAggregator

      # @return [Sequel::Database] the underlying Sequel database connection
      attr_reader :db

      # Open (or create) a SQLite database and migrate to the current schema.
      # @param db_path [String] filesystem path to the SQLite database file
      def initialize(db_path)
        @db_path = db_path
        @db = connect_database(db_path)

        ensure_schema!
      end

      # Disconnect from the database.
      # @return [void]
      def close
        @db.disconnect
      end

      # Lazily-initialized vector index for semantic search.
      # @return [Index::VectorIndex]
      def vector_index
        @vector_index ||= Index::VectorIndex.new(self)
      end

      # Checkpoint the WAL file to prevent unlimited growth.
      # @return [void]
      def checkpoint_wal
        @db.run("PRAGMA wal_checkpoint(TRUNCATE)")
      end

      # Current schema version stored in the meta table.
      # @return [Integer, nil]
      def schema_version
        @db[:meta].where(key: "schema_version").get(:value)&.to_i
      end

      # --- Table accessors ---
      # Each returns a {Sequel::Dataset} bound to the corresponding table.

      # @return [Sequel::Dataset]
      def content_items = @db[:content_items]

      # @return [Sequel::Dataset]
      def delta_cursors = @db[:delta_cursors]

      # @return [Sequel::Dataset]
      def entities = @db[:entities]

      # @return [Sequel::Dataset]
      def entity_aliases = @db[:entity_aliases]

      # @return [Sequel::Dataset]
      def facts = @db[:facts]

      # @return [Sequel::Dataset]
      def provenance = @db[:provenance]

      # @return [Sequel::Dataset]
      def fact_links = @db[:fact_links]

      # @return [Sequel::Dataset]
      def conflicts = @db[:conflicts]

      # @return [Sequel::Dataset]
      def tool_calls = @db[:tool_calls]

      # @return [Sequel::Dataset]
      def operation_progress = @db[:operation_progress]

      # @return [Sequel::Dataset]
      def schema_health = @db[:schema_health]

      # @return [Sequel::Dataset]
      def ingestion_metrics = @db[:ingestion_metrics]

      # @return [Sequel::Dataset]
      def llm_cache = @db[:llm_cache]

      # @return [Sequel::Dataset]
      def mcp_tool_calls = @db[:mcp_tool_calls]

      # @return [Sequel::Dataset]
      def activity_events = @db[:activity_events]

      # @return [Sequel::Dataset]
      def moment_feedback = @db[:moment_feedback]

      # @return [Sequel::Dataset]
      def otel_metrics = @db[:otel_metrics]

      # @return [Sequel::Dataset]
      def otel_events = @db[:otel_events]

      # @return [Sequel::Dataset]
      def otel_traces = @db[:otel_traces]

      # @return [Sequel::Dataset]
      def observations = @db[:observations]

      # Upsert a thumbs-up/down verdict for a moment. One row per event_id
      # (unique constraint on the column) — repeat clicks overwrite. Returns
      # the persisted row.
      #
      # @param event_id [Integer] activity_events row id
      # @param verdict [String] "up" or "down"
      # @param note [String, nil] optional freeform note
      # @param recorded_at [String, nil] ISO 8601 timestamp (defaults to now UTC)
      # @return [Hash] row after upsert
      def upsert_moment_feedback(event_id:, verdict:, note: nil, recorded_at: nil)
        raise ArgumentError, "verdict must be 'up' or 'down'" unless %w[up down].include?(verdict)

        ts = recorded_at || Time.now.utc.iso8601
        with_retry do
          @db.transaction do
            existing = moment_feedback.where(event_id: event_id).first
            if existing
              moment_feedback.where(id: existing[:id]).update(
                verdict: verdict, note: note, recorded_at: ts
              )
              moment_feedback.where(id: existing[:id]).first
            else
              id = moment_feedback.insert(
                event_id: event_id, verdict: verdict, note: note, recorded_at: ts
              )
              moment_feedback.where(id: id).first
            end
          end
        end
      end

      # Remove the verdict for a moment, if any.
      # @return [Integer] number of rows deleted (0 or 1)
      def clear_moment_feedback(event_id)
        with_retry { moment_feedback.where(event_id: event_id).delete }
      end

      # Record a single MCP tool invocation for telemetry.
      # Inserts synchronously; callers wrap in with_retry at the call site
      # if needed.
      #
      # @param tool_name [String] name of the MCP tool invoked
      # @param duration_ms [Integer] execution time in milliseconds
      # @param result_count [Integer, nil] number of results returned
      # @param scope [String, nil] "global" or "project"
      # @param error_class [String, nil] error class name if the call failed
      # @param called_at [String, nil] ISO 8601 timestamp (defaults to now UTC)
      # @return [Integer] inserted row id
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

      # Insert one OTel metric data point. Two value columns let us preserve
      # int64 precision for counters (token counts) without losing fidelity in
      # Float — see migration 018.
      #
      # @param name [String] OTel metric name (e.g. "claude_code.token.usage")
      # @param value_type [String] "int" or "double"
      # @param value_int [Integer, nil] integer value when value_type == "int"
      # @param value_float [Float, nil] float value when value_type == "double"
      # @param unit [String, nil] OTel unit string ("tokens", "USD", "s", ...)
      # @param attributes [Hash, nil] flattened attribute map
      # @param resource [Hash, nil] resource attribute map
      # @param recorded_at [String] ISO 8601 timestamp
      # @return [Integer] inserted row id
      def insert_otel_metric(name:, value_type:, recorded_at:, value_int: nil, value_float: nil,
        unit: nil, attributes: nil, resource: nil)
        otel_metrics.insert(otel_metric_row(
          name: name, value_type: value_type, recorded_at: recorded_at,
          value_int: value_int, value_float: value_float, unit: unit,
          attributes: attributes, resource: resource
        ))
      end

      # Bulk insert OTel metric rows in a single SQL statement. Hot-path
      # callers (the OTLP receiver) batch dozens of points per request;
      # multi_insert avoids the per-row prepare/bind overhead.
      def bulk_insert_otel_metrics(rows)
        return 0 if rows.empty?
        otel_metrics.multi_insert(rows.map { |r| otel_metric_row(**r) })
        rows.size
      end

      # Insert one OTel log-style event row.
      #
      # @param event_name [String] e.g. "user_prompt", "tool_result", "api_request"
      # @param occurred_at [String] ISO 8601 timestamp
      # @param session_id [String, nil]
      # @param prompt_id [String, nil] UUID correlating events from one prompt
      # @param attributes [Hash, nil]
      # @param resource [Hash, nil]
      # @return [Integer] inserted row id
      def insert_otel_event(event_name:, occurred_at:, session_id: nil, prompt_id: nil,
        attributes: nil, resource: nil)
        otel_events.insert(otel_event_row(
          event_name: event_name, occurred_at: occurred_at,
          session_id: session_id, prompt_id: prompt_id,
          attributes: attributes, resource: resource
        ))
      end

      def bulk_insert_otel_events(rows)
        return 0 if rows.empty?
        otel_events.multi_insert(rows.map { |r| otel_event_row(**r) })
        rows.size
      end

      # Insert one OTel trace span row. Only used when traces are explicitly
      # opted in via Configuration#otel_traces_enabled?.
      #
      # @param trace_id [String]
      # @param span_id [String]
      # @param name [String]
      # @param recorded_at [String]
      # @param parent_span_id [String, nil]
      # @param session_id [String, nil]
      # @param prompt_id [String, nil]
      # @param start_unix_nano [Integer, nil]
      # @param end_unix_nano [Integer, nil]
      # @param duration_ms [Integer, nil]
      # @param status_code [String, nil]
      # @param attributes [Hash, nil]
      # @param resource [Hash, nil]
      # @return [Integer] inserted row id
      def insert_otel_trace_span(trace_id:, span_id:, name:, recorded_at:,
        parent_span_id: nil, session_id: nil, prompt_id: nil,
        start_unix_nano: nil, end_unix_nano: nil, duration_ms: nil,
        status_code: nil, attributes: nil, resource: nil)
        otel_traces.insert(otel_trace_row(
          trace_id: trace_id, span_id: span_id, name: name, recorded_at: recorded_at,
          parent_span_id: parent_span_id, session_id: session_id, prompt_id: prompt_id,
          start_unix_nano: start_unix_nano, end_unix_nano: end_unix_nano,
          duration_ms: duration_ms, status_code: status_code,
          attributes: attributes, resource: resource
        ))
      end

      def bulk_insert_otel_traces(rows)
        return 0 if rows.empty?
        otel_traces.multi_insert(rows.map { |r| otel_trace_row(**r) })
        rows.size
      end

      private

      def otel_metric_row(name:, value_type:, recorded_at:, value_int: nil, value_float: nil,
        unit: nil, attributes: nil, resource: nil)
        {
          name: name, value_type: value_type, value_int: value_int, value_float: value_float,
          unit: unit, attributes_json: attributes&.to_json, resource_json: resource&.to_json,
          recorded_at: recorded_at
        }
      end

      def otel_event_row(event_name:, occurred_at:, session_id: nil, prompt_id: nil,
        attributes: nil, resource: nil)
        {
          event_name: event_name, session_id: session_id, prompt_id: prompt_id,
          attributes_json: attributes&.to_json, resource_json: resource&.to_json,
          occurred_at: occurred_at
        }
      end

      def otel_trace_row(trace_id:, span_id:, name:, recorded_at:,
        parent_span_id: nil, session_id: nil, prompt_id: nil,
        start_unix_nano: nil, end_unix_nano: nil, duration_ms: nil,
        status_code: nil, attributes: nil, resource: nil)
        {
          trace_id: trace_id, span_id: span_id, parent_span_id: parent_span_id,
          name: name, session_id: session_id, prompt_id: prompt_id,
          start_unix_nano: start_unix_nano, end_unix_nano: end_unix_nano,
          duration_ms: duration_ms, status_code: status_code,
          attributes_json: attributes&.to_json, resource_json: resource&.to_json,
          recorded_at: recorded_at
        }
      end

      public

      # --- Content items ---

      # Insert a content item or return the existing id if a duplicate
      # (same text_hash + session_id) already exists. Wrapped in retry logic.
      #
      # @param source [String] origin type (e.g. "transcript", "hook")
      # @param text_hash [String] SHA-256 hex digest of the raw text
      # @param byte_len [Integer] byte length of the raw text
      # @param session_id [String, nil] Claude Code session identifier
      # @param transcript_path [String, nil] filesystem path to the transcript file
      # @param project_path [String, nil] project directory path
      # @param occurred_at [String, nil] ISO 8601 timestamp (defaults to now UTC)
      # @param raw_text [String, nil] original text content
      # @param metadata [Hash, nil] additional metadata stored as JSON
      # @param git_branch [String, nil] active git branch at ingestion time
      # @param cwd [String, nil] working directory at ingestion time
      # @param claude_version [String, nil] Claude Code version string
      # @param thinking_level [String, nil] thinking level setting
      # @param source_mtime [String, nil] ISO 8601 mtime of the source file
      # @return [Integer] content item row id (existing or newly inserted)
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

      # Fetch a single content item by primary key.
      # @param id [Integer] content item id
      # @return [Hash, nil]
      def get_content_item(id)
        content_items.where(id: id).first
      end

      # Find a content item by transcript path and source modification time.
      # @param transcript_path [String] filesystem path to the transcript
      # @param mtime_iso8601 [String] ISO 8601 modification timestamp
      # @return [Hash, nil]
      def content_item_by_transcript_and_mtime(transcript_path, mtime_iso8601)
        content_items
          .where(transcript_path: transcript_path, source_mtime: mtime_iso8601)
          .first
      end

      # --- Tool calls ---

      # Bulk-insert tool call records for a content item.
      # @param content_item_id [Integer] owning content item id
      # @param tool_calls_data [Array<Hash>] tool call hashes with keys
      #   :tool_name, :tool_input, :tool_result, :compressed_summary,
      #   :is_error, :timestamp
      # @return [void]
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

      # Retrieve tool calls for a content item, ordered by timestamp.
      # @param content_item_id [Integer] content item id
      # @return [Array<Hash>]
      def tool_calls_for_content_item(content_item_id)
        tool_calls
          .where(content_item_id: content_item_id)
          .order(:timestamp)
          .all
      end

      # --- Delta cursors ---

      # Get the last-read byte offset for a session/transcript pair.
      # @param session_id [String] session identifier
      # @param transcript_path [String] transcript file path
      # @return [Integer, nil] byte offset, or nil if no cursor exists
      def get_delta_cursor(session_id, transcript_path)
        delta_cursors.where(session_id: session_id, transcript_path: transcript_path).get(:last_byte_offset)
      end

      # Create or update the byte-offset cursor for a session/transcript pair.
      # @param session_id [String] session identifier
      # @param transcript_path [String] transcript file path
      # @param offset [Integer] new byte offset
      # @return [void]
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

      # Find an entity by its slug or create a new one.
      # @param type [String] entity type (e.g. "database", "framework", "person")
      # @param name [String] canonical entity name
      # @return [Integer] entity row id
      def find_or_create_entity(type:, name:)
        slug = slugify(type, name)
        existing = entities.where(slug: slug).get(:id)
        return existing if existing

        now = Time.now.utc.iso8601
        entities.insert(type: type, canonical_name: name, slug: slug, created_at: now)
      end

      # --- Facts ---

      # Insert a new fact (subject-predicate-object triple) with an auto-generated docid.
      #
      # @param subject_entity_id [Integer] entity id for the subject
      # @param predicate [String] predicate label (e.g. "uses_database", "depends_on")
      # @param object_entity_id [Integer, nil] entity id for the object (if entity-valued)
      # @param object_literal [String, nil] literal value for the object
      # @param datatype [String, nil] datatype hint for the object literal
      # @param polarity [String] "positive" or "negative"
      # @param valid_from [String, nil] ISO 8601 validity start (defaults to now UTC)
      # @param status [String] fact status ("active", "superseded", "rejected")
      # @param confidence [Float] confidence score 0.0..1.0
      # @param created_from [String, nil] provenance tag (e.g. "promoted:path:id")
      # @param scope [String] "global" or "project"
      # @param project_path [String, nil] project directory for project-scoped facts
      # @return [Integer] inserted fact row id
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

      # Look up a fact by its short document identifier.
      # @param docid [String] 8-character hex document id
      # @return [Hash, nil]
      def find_fact_by_docid(docid)
        facts.where(docid: docid).first
      end

      # Selectively update one or more fields on a fact.
      # Only provided (non-nil) keyword arguments are written. Setting scope
      # to "global" automatically clears project_path.
      #
      # @param fact_id [Integer] fact row id
      # @param status [String, nil] new status value
      # @param valid_to [String, nil] ISO 8601 end-of-validity timestamp
      # @param scope [String, nil] "global" or "project"
      # @param project_path [String, nil] project directory (cleared when scope is "global")
      # @param embedding [Array<Float>, nil] embedding vector to store as JSON
      # @return [Boolean] true if any fields were updated, false if all args were nil
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

      # Overwrite the embedding vector for a fact.
      # @param fact_id [Integer] fact row id
      # @param embedding_vector [Array<Float>] embedding to store as JSON
      # @return [void]
      def update_fact_embedding(fact_id, embedding_vector)
        facts.where(id: fact_id).update(embedding_json: embedding_vector.to_json)
      end

      # Reject a fact as incorrect (e.g. a distiller hallucination).
      # Sets status to "rejected", closes any open conflicts involving
      # the fact, and records the reason in conflict notes when provided.
      # All updates run in a single transaction.
      #
      # @param fact_id [Integer] fact row id to reject
      # @param reason [String, nil] optional rejection reason appended to conflict notes
      # @return [Hash, nil] +{rejected: true, conflicts_resolved: Integer}+
      #   or nil if the fact does not exist
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

      # Retrieve active facts that have stored embeddings.
      # @param limit [Integer] maximum rows to return
      # @return [Array<Hash>] fact rows with :id, :subject_entity_id,
      #   :predicate, :object_literal, :embedding_json, :scope
      def facts_with_embeddings(limit: 1000)
        facts
          .where(Sequel.~(embedding_json: nil))
          .where(status: "active")
          .select(:id, :subject_entity_id, :predicate, :object_literal, :embedding_json, :scope)
          .limit(limit)
          .all
      end

      # Find all facts for a given subject + predicate combination (a "slot").
      # Used by the resolver to detect supersession and conflicts.
      # @param subject_entity_id [Integer] subject entity id
      # @param predicate [String] predicate label
      # @param status [String] filter by status (default: "active")
      # @return [Array<Hash>]
      def facts_for_slot(subject_entity_id, predicate, status: "active")
        facts
          .where(subject_entity_id: subject_entity_id, predicate: predicate, status: status)
          .select(:id, :subject_entity_id, :predicate, :object_entity_id, :object_literal,
            :datatype, :polarity, :valid_from, :valid_to, :status, :confidence,
            :created_from, :created_at)
          .all
      end

      # --- Provenance ---

      # Record a provenance link between a fact and its source evidence.
      #
      # @param fact_id [Integer] fact row id
      # @param content_item_id [Integer, nil] source content item id
      # @param quote [String, nil] verbatim quote from the source
      # @param attribution_entity_id [Integer, nil] entity who stated the fact
      # @param strength [String] evidence strength ("stated", "inferred", "derived")
      # @param line_start [Integer, nil] starting line in source content
      # @param line_end [Integer, nil] ending line in source content
      # @return [Integer] inserted provenance row id
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

      # Retrieve all provenance records for a given fact.
      # @param fact_id [Integer] fact row id
      # @return [Array<Hash>]
      def provenance_for_fact(fact_id)
        provenance.where(fact_id: fact_id).all
      end

      # --- Conflicts & fact links ---

      # Record a conflict between two facts.
      # @param fact_a_id [Integer] first conflicting fact id
      # @param fact_b_id [Integer] second conflicting fact id
      # @param status [String] conflict status ("open" or "resolved")
      # @param notes [String, nil] human-readable notes about the conflict
      # @return [Integer] inserted conflict row id
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

      # Retrieve all unresolved conflicts.
      # @return [Array<Hash>]
      def open_conflicts
        conflicts.where(status: "open").all
      end

      # Create a directional link between two facts (e.g. supersession).
      # @param from_fact_id [Integer] source fact id
      # @param to_fact_id [Integer] target fact id
      # @param link_type [String] relationship type (e.g. "supersedes", "conflicts_with")
      # @return [Integer] inserted fact_link row id
      def insert_fact_link(from_fact_id:, to_fact_id:, link_type:)
        fact_links.insert(from_fact_id: from_fact_id, to_fact_id: to_fact_id, link_type: link_type)
      end

      # --- Ingestion metrics ---

      # Fetch content items that have not yet been distilled, ordered newest first.
      # @param limit [Integer] maximum rows to return
      # @param min_length [Integer] minimum byte_len threshold
      # @return [Array<Hash>]
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

      # --- Observations (episodic layer) ---

      # Insert an episodic observation. token_count is estimated from the body
      # when not supplied (rough ~4 chars/token) so Phase 2 budget math has a
      # value to work with.
      #
      # @param body [String] dense narrative text (required)
      # @param kind [String] one of Domain::Observation::KINDS
      # @param priority [Integer] 1=important, 2=maybe, 3=info
      # @param scope [String] "project" or "global"
      # @param project_path [String, nil] project directory for project-scoped rows
      # @param source_content_item_id [Integer, nil] provenance link to the raw chunk
      # @param session_id [String, nil] session that produced the observation
      # @param observed_at [String, nil] ISO 8601 event time (defaults to now UTC)
      # @param token_count [Integer, nil] precomputed token estimate
      # @return [Integer] inserted observation row id
      def insert_observation(body:, kind: "event", priority: 3, scope: "project",
        project_path: nil, source_content_item_id: nil, session_id: nil,
        observed_at: nil, token_count: nil)
        now = Time.now.utc.iso8601
        with_retry("insert_observation") do
          observations.insert(
            body: body,
            kind: kind,
            priority: priority,
            scope: scope,
            project_path: project_path,
            source_content_item_id: source_content_item_id,
            token_count: token_count || (body.length / 4.0).ceil,
            status: "active",
            session_id: session_id,
            observed_at: observed_at || now,
            created_at: now
          )
        end
      end

      # Fetch active observations, newest first. Used by the memory.observations
      # MCP tool and (later) the stable-prefix injection.
      #
      # @param scope [String, nil] filter by "project"/"global"; nil for any
      # @param limit [Integer] maximum rows to return
      # @param min_priority [Integer, nil] only rows with priority <= this
      #   (1 returns only 🔴; nil returns all)
      # @return [Array<Hash>]
      def recent_observations(scope: nil, limit: 20, min_priority: nil)
        ds = observations.where(status: "active")
        ds = ds.where(scope: scope) if scope
        ds = ds.where { priority <= min_priority } if min_priority
        ds.order(Sequel.desc(:observed_at), Sequel.desc(:id)).limit(limit).all
      end

      # Tombstone an observation by pointing it at the consolidated row that
      # replaced it (append-only supersession — the row is preserved, not
      # deleted, mirroring fact_links). Used by the Reflector.
      #
      # @param observation_id [Integer] the superseded observation
      # @param into_id [Integer] the consolidated observation it was merged into
      # @return [Boolean] true if a row was updated
      def tombstone_observation(observation_id, into_id:)
        now = Time.now.utc.iso8601
        updated = observations.where(id: observation_id).update(
          status: "consolidated", consolidated_into: into_id, reflected_at: now
        )
        updated > 0
      end

      # Retire a stale observation (status "expired") without a consolidation
      # target. Append-only — the row is preserved for provenance, just
      # excluded from active recall. Used by the Reflector's TTL pass.
      #
      # @param observation_id [Integer]
      # @return [Boolean] true if a row was updated
      def expire_observation(observation_id)
        now = Time.now.utc.iso8601
        updated = observations.where(id: observation_id).update(status: "expired", reflected_at: now)
        updated > 0
      end

      # Fold a duplicate's sighting count into the keeper. Called by the
      # Reflector's dedup pass so corroboration survives consolidation — the
      # signal the promotion gate keys off.
      #
      # @param observation_id [Integer] keeper observation
      # @param by [Integer] how much to add (the loser's corroboration_count)
      # @return [void]
      def increment_corroboration(observation_id, by: 1)
        observations.where(id: observation_id)
          .update(corroboration_count: Sequel[:corroboration_count] + by)
      end

      # Mark an observation as promoted to a structured fact. Append-only: the
      # row is preserved (provenance), it just stops being a promotion
      # candidate.
      #
      # @param observation_id [Integer]
      # @param fact_id [Integer] the fact this observation was promoted into
      # @return [Boolean] true if a row was updated
      def mark_observation_promoted(observation_id, fact_id:)
        now = Time.now.utc.iso8601
        updated = observations.where(id: observation_id)
          .update(promoted_at: now, promoted_fact_id: fact_id, reflected_at: now)
        updated > 0
      end

      # Active, not-yet-promoted observations corroborated at least
      # `min_corroboration` times — i.e. eligible for promotion to a fact.
      # Highest corroboration first.
      #
      # @param scope [String, nil] filter by scope; nil for any
      # @param min_corroboration [Integer] sightings required (the gate)
      # @param limit [Integer]
      # @return [Array<Hash>]
      def promotion_candidates(scope: nil, min_corroboration: 2, limit: 10)
        ds = observations.where(status: "active", promoted_at: nil)
        ds = ds.where(scope: scope) if scope
        ds.where { corroboration_count >= min_corroboration }
          .order(Sequel.desc(:corroboration_count), Sequel.desc(:observed_at))
          .limit(limit)
          .all
      end

      # --- Meta ---

      # Set a key-value pair in the meta table (upsert).
      # @param key [String] metadata key
      # @param value [String] metadata value
      # @return [void]
      def set_meta(key, value)
        @db[:meta].insert_conflict(target: :key, update: {value: value}).insert(key: key, value: value)
      end

      # Retrieve a value from the meta table.
      # @param key [String] metadata key
      # @return [String, nil]
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
