# frozen_string_literal: true

module ClaudeMemory
  module Sweep
    # Clean separation of individual maintenance operations from Sweeper's
    # budget-management orchestration. Each method performs a single operation
    # and returns the count of affected records.
    #
    # Source: QMD v2.0.1 Maintenance class pattern
    class Maintenance
      DEFAULT_CONFIG = {
        proposed_fact_ttl_days: 14,
        disputed_fact_ttl_days: 30,
        content_retention_days: 30,
        mcp_tool_call_retention_days: 90,
        otel_metric_retention_days: 30,
        otel_event_retention_days: 14,
        otel_trace_retention_days: 7,
        observation_info_ttl_days: 30,
        stale_fact_threshold_days: 180,
        ratify_window_days: 30
      }.freeze

      attr_reader :store

      def initialize(store, config: {})
        @store = store
        @config = DEFAULT_CONFIG.merge(config)
      end

      # Expire proposed facts older than TTL.
      # Returns: Integer count of expired facts
      def expire_proposed_facts
        cutoff = cutoff_time(@config[:proposed_fact_ttl_days])
        @store.facts
          .where(status: "proposed")
          .where { created_at < cutoff }
          .update(status: "expired")
      end

      # Stage 1 of the two-stage expiry lifecycle (#14): active → expiring.
      # Uses the StaleDetector predicate (created + last recall both past the
      # threshold) plus reaffirmed_at — an explicitly ratified fact is fresh
      # even if nothing has recalled it. Expiring facts still recall
      # (annotated, down-weighted); this only starts the ratification clock.
      # Returns: Integer count of facts moved to expiring
      def mark_expiring_facts
        cutoff = cutoff_time(@config[:stale_fact_threshold_days])
        @store.facts
          .where(status: "active")
          .where { created_at < cutoff }
          .where { (last_recalled_at < cutoff) | {last_recalled_at: nil} }
          .where { (reaffirmed_at < cutoff) | {reaffirmed_at: nil} }
          .update(status: "expiring", expiring_since: Time.now.utc.iso8601)
      end

      # Stage 2 (#14): expiring → expired after ratify_window_days without
      # ratification. Ratifying returns a fact to active and clears
      # expiring_since, so anything still expiring past the window is
      # unratified by definition. Expired facts are excluded from default
      # recall (like superseded) but never deleted.
      # Returns: Integer count of expired facts
      def expire_unratified_facts
        cutoff = cutoff_time(@config[:ratify_window_days])
        @store.facts
          .where(status: "expiring")
          .where { expiring_since < cutoff }
          .update(status: "expired")
      end

      # Expire disputed facts older than TTL.
      # Returns: Integer count of expired facts
      def expire_disputed_facts
        cutoff = cutoff_time(@config[:disputed_fact_ttl_days])
        @store.facts
          .where(status: "disputed")
          .where { created_at < cutoff }
          .update(status: "expired")
      end

      # Collapse duplicate multi-value facts. Before the resolver-level
      # dedup fix (2026-04-17), multi-value predicates like uses_language
      # and uses_framework accumulated identical rows every ingest cycle.
      # For each (subject_entity_id, predicate, object_literal, scope) group
      # with more than one active fact, keep the oldest row, copy the
      # duplicates' provenance onto the keeper (so we retain source
      # signal), and mark the duplicates superseded. Returns the count of
      # fact rows merged into their keeper.
      def dedupe_multi_value_facts
        merged = 0
        @store.db.transaction do
          # Pull every active fact with a literal object and group in Ruby.
          # Facts tables stay small (< 10k typical); Sequel's HAVING COUNT(*)
          # path hits adapter quoting bugs on some Extralite versions.
          active = @store.facts
            .where(status: "active")
            .exclude(subject_entity_id: nil)
            .exclude(object_literal: nil)
            .order(:id)
            .all

          groups = active.group_by { |f|
            [f[:subject_entity_id], f[:predicate], f[:object_literal]&.downcase, f[:scope]]
          }

          groups.each_value do |rows|
            next if rows.size < 2

            keeper = rows.first
            rows[1..].each do |loser|
              @store.provenance.where(fact_id: loser[:id]).update(fact_id: keeper[:id])
              @store.facts.where(id: loser[:id]).update(
                status: "superseded",
                valid_to: Time.now.utc.iso8601
              )
              @store.insert_fact_link(from_fact_id: keeper[:id], to_fact_id: loser[:id], link_type: "supersedes")
              merged += 1
            end
          end
        end
        merged
      end

      # Fix scope leakage: facts whose `scope` column disagrees with the
      # store they live in. Pre-2026-04-20, the resolver treated
      # scope_hint from the distiller as a scope override — so when the
      # NullDistiller detected global-scope language ("always", "my
      # preference"), it stamped scope: "global" on facts that still
      # ended up written to the project DB. The result was invisible
      # orphaned rows: not in the global DB so global recall never saw
      # them, but labeled global inside the project DB.
      #
      # This pass detects those rows by comparing `scope` to the
      # expected value derived from which DB this Maintenance instance
      # is running against, and rewrites scope + project_path to match.
      # Does not move facts between DBs — users can `claude-memory
      # promote <id>` to do a proper cross-store copy.
      # Returns: Integer count of facts whose scope was corrected.
      def fix_scope_leakage
        expected = expected_scope_for_store
        return 0 unless expected

        project_path_for_scope = (expected == "global") ? nil : detect_project_path
        @store.facts
          .exclude(scope: expected)
          .update(scope: expected, project_path: project_path_for_scope)
      end

      # Delete provenance records referencing non-existent facts.
      # Returns: Integer count of deleted provenance rows
      def prune_orphaned_provenance
        fact_ids = @store.facts.select(:id)
        @store.provenance
          .exclude(fact_id: fact_ids)
          .delete
      end

      # Delete old content items not referenced by any provenance.
      # Also removes their FTS index entries.
      # Returns: Integer count of deleted content items
      def prune_old_content
        cutoff = cutoff_time(@config[:content_retention_days])
        referenced_ids = @store.provenance.exclude(content_item_id: nil).select(:content_item_id)
        prunable = @store.content_items
          .where { ingested_at < cutoff }
          .exclude(id: referenced_ids)

        fts = ClaudeMemory::Index::LexicalFTS.new(@store)
        prunable.select(:id, :raw_text).each do |row|
          fts.remove_content_item(row[:id], row[:raw_text])
        rescue
          # [ANTI-PATTERN IGNORED]: FTS entry may not exist for this row; best-effort removal during GC
        end

        prunable.delete
      end

      # Backfill vector index for unindexed facts.
      # Returns: Integer count of backfilled embeddings (0 if unavailable)
      def backfill_vec_index(limit: 100)
        with_vec_index do |vec_index|
          return vec_index.backfill_batch!(limit: limit)
        end
        0
      end

      # Remove vector embeddings for superseded/expired facts.
      # Returns: Integer count of cleaned embeddings (0 if unavailable)
      def cleanup_vec_expired(limit: 100)
        with_vec_index do |vec_index|
          stale_ids = @store.facts
            .where(status: %w[superseded expired])
            .where(Sequel.~(vec_indexed_at: nil))
            .select(:id)
            .limit(limit)
            .map { |r| r[:id] }

          stale_ids.each { |fact_id| vec_index.remove_embedding(fact_id) }
          return stale_ids.size
        end
        0
      end

      # Delete MCP tool-call telemetry rows older than retention window.
      # Returns: Integer count of deleted rows (0 if table missing).
      def prune_old_mcp_tool_calls
        return 0 unless @store.db.table_exists?(:mcp_tool_calls)

        cutoff = cutoff_time(@config[:mcp_tool_call_retention_days])
        @store.mcp_tool_calls.where { called_at < cutoff }.delete
      end

      # Delete OTel metric data points older than retention window.
      # Returns: Integer count of deleted rows (0 if table missing).
      def prune_old_otel_metrics
        return 0 unless @store.db.table_exists?(:otel_metrics)

        cutoff = cutoff_time(@config[:otel_metric_retention_days])
        @store.otel_metrics.where { recorded_at < cutoff }.delete
      end

      # Delete OTel log-style events older than retention window.
      # Returns: Integer count of deleted rows (0 if table missing).
      def prune_old_otel_events
        return 0 unless @store.db.table_exists?(:otel_events)

        cutoff = cutoff_time(@config[:otel_event_retention_days])
        @store.otel_events.where { occurred_at < cutoff }.delete
      end

      # Delete OTel trace spans older than retention window.
      # Returns: Integer count of deleted rows (0 if table missing).
      def prune_old_otel_traces
        return 0 unless @store.db.table_exists?(:otel_traces)

        cutoff = cutoff_time(@config[:otel_trace_retention_days])
        @store.otel_traces.where { recorded_at < cutoff }.delete
      end

      # Checkpoint the SQLite WAL file for compaction.
      # Returns: true
      def checkpoint_wal
        @store.checkpoint_wal
        true
      end

      # Run the deterministic observation Reflector (dedupe near-identical
      # observations + expire stale info-level ones). Free, no LLM —
      # provenance-preserving (tombstone, never delete).
      # Returns: Hash {deduped:, expired:}
      def reflect_observations
        return {deduped: 0, expired: 0} unless @store.db.table_exists?(:observations)

        result = ClaudeMemory::Observe::Reflector.new(
          @store, info_ttl_days: @config[:observation_info_ttl_days]
        ).reflect!
        {deduped: result.deduped, expired: result.expired}
      end

      # Self-heal the FTS5 rank index (improvement #69). Concurrent writers
      # (the ingest hook vs the MCP server) can leave content_fts in a state
      # where plain MATCH works but `ORDER BY rank` raises "malformed" —
      # silently breaking recall while integrity_check passes. Sweep runs on
      # PreCompact/SessionEnd, so probing the rank path here and rebuilding on
      # failure lets recall self-repair within the session that broke it, with
      # no manual `claude-memory compact`. (Detection is also surfaced by the
      # doctor FtsRankCheck; this is the automatic repair.) A rebuild on a very
      # large index runs to completion — corruption is rare and the rebuild is
      # the only fix; the per-step budget gate keeps it from *starting* late.
      # Returns: true if a rebuild was performed, false otherwise.
      def repair_fts_rank
        fts = ClaudeMemory::Index::LexicalFTS.new(@store)
        fts.search("a", limit: 1)
        false
      rescue ClaudeMemory::Index::LexicalFTS::CorruptRankIndexError
        fts.rebuild!
        true
      rescue
        false
      end

      # Run SQLite VACUUM to reclaim space.
      # Returns: true
      def vacuum
        @store.db.run("VACUUM")
        true
      end

      private

      def cutoff_time(days)
        (Time.now - days * 86400).utc.iso8601
      end

      # Infer the scope each store is supposed to carry by comparing its
      # DB path to the canonical Configuration paths. Returns "global" for
      # the user-wide DB, "project" for the per-project DB, or nil when
      # the path doesn't match either (custom test paths, etc. — in which
      # case fix_scope_leakage is a no-op).
      def expected_scope_for_store
        path = @store.db.opts[:database].to_s
        return nil if path.empty?
        config = ClaudeMemory::Configuration.new
        return "global" if File.expand_path(path) == File.expand_path(config.global_db_path)

        # Project DB lives at <project>/.claude/memory.sqlite3 — we can
        # always check whether the DB path sits under a .claude directory
        # to classify it as project-scoped regardless of which project.
        File.dirname(File.expand_path(path)).end_with?("/.claude") ? "project" : nil
      end

      def detect_project_path
        path = @store.db.opts[:database].to_s
        return nil if path.empty?
        # The canonical project DB lives at <project>/.claude/memory.sqlite3
        # so the project path is two levels up.
        project = File.dirname(File.expand_path(path), 2)
        Dir.exist?(project) ? project : nil
      end

      def with_vec_index
        vec_index = @store.vector_index
        return unless vec_index.available?
        yield vec_index
      end
    end
  end
end
