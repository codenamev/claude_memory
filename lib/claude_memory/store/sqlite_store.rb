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
    # SQLite-backed fact store for ClaudeMemory.
    # Manages all database tables (content_items, entities, facts, provenance,
    # conflicts, fact_links, etc.) via Sequel with Extralite adapter.
    # Includes RetryHandler for transient lock recovery and SchemaManager
    # for automatic migrations on open.
    class SQLiteStore
      include RetryHandler
      include SchemaManager

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

      # Count content items that have not yet been distilled.
      # @param min_length [Integer] minimum byte_len threshold
      # @return [Integer]
      def count_undistilled(min_length: 200)
        content_items
          .left_join(:ingestion_metrics, content_item_id: :id)
          .where(Sequel[:ingestion_metrics][:id] => nil)
          .where { byte_len >= min_length }
          .count
      end

      # Record token usage and extraction counts for a distillation run.
      # @param content_item_id [Integer] content item that was distilled
      # @param input_tokens [Integer] LLM input tokens consumed
      # @param output_tokens [Integer] LLM output tokens consumed
      # @param facts_extracted [Integer] number of facts extracted
      # @return [Integer] inserted row id
      def record_ingestion_metrics(content_item_id:, input_tokens:, output_tokens:, facts_extracted:)
        ingestion_metrics.insert(
          content_item_id: content_item_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          facts_extracted: facts_extracted,
          created_at: Time.now.utc.iso8601
        )
      end

      # Compute aggregate ingestion metrics across all distillation runs.
      # @return [Hash, nil] totals and efficiency ratio, or nil if no data
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

      # Mark all undistilled content items as distilled with zero token counts.
      # Used for backfilling legacy content that predates the metrics table.
      # @return [Integer] number of items backfilled
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

      # Look up a cached LLM result by its cache key.
      # @param cache_key [String] SHA-256 hex cache key
      # @return [Hash, nil]
      def llm_cache_lookup(cache_key)
        llm_cache.where(cache_key: cache_key).first
      end

      # Store or update a cached LLM result. Uses upsert on the cache_key.
      # @param operation [String] operation name (e.g. "distill", "embed")
      # @param model [String] model identifier
      # @param input_hash [String] SHA-256 hex digest of the input
      # @param result_json [String] JSON-serialized result
      # @param input_tokens [Integer, nil] input tokens consumed
      # @param output_tokens [Integer, nil] output tokens consumed
      # @return [void]
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

      # Compute the cache key for an LLM operation.
      # @param operation [String] operation name
      # @param model [String] model identifier
      # @param input [String] raw input text
      # @return [String] SHA-256 hex cache key
      def llm_cache_key(operation, model, input)
        input_hash = Digest::SHA256.hexdigest(input)
        Digest::SHA256.hexdigest("#{operation}:#{model}:#{input_hash}")
      end

      # Delete LLM cache entries older than the given age.
      # @param max_age_seconds [Integer] maximum age in seconds (default: 7 days)
      # @return [Integer] number of rows deleted
      def llm_cache_prune(max_age_seconds: 604_800)
        cutoff = (Time.now - max_age_seconds).utc.iso8601
        llm_cache.where { created_at < cutoff }.delete
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
