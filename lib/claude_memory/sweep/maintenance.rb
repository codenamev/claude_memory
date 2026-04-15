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
        mcp_tool_call_retention_days: 90
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

      # Expire disputed facts older than TTL.
      # Returns: Integer count of expired facts
      def expire_disputed_facts
        cutoff = cutoff_time(@config[:disputed_fact_ttl_days])
        @store.facts
          .where(status: "disputed")
          .where { created_at < cutoff }
          .update(status: "expired")
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
          # FTS entry may not exist; skip
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

      # Checkpoint the SQLite WAL file for compaction.
      # Returns: true
      def checkpoint_wal
        @store.checkpoint_wal
        true
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

      def with_vec_index
        vec_index = @store.vector_index
        return unless vec_index.available?
        yield vec_index
      end
    end
  end
end
