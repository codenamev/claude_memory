# frozen_string_literal: true

module ClaudeMemory
  module Sweep
    # Clean separation of individual maintenance operations from Sweeper's
    # budget-management orchestration. Each method performs a single operation
    # and returns the count of affected records.
    #
    # Source: QMD v2.0.1 Maintenance class pattern
    class Maintenance
      # Short / noise tokens dropped before Jaccard comparison.
      # Intentionally minimal — we want conservative token extraction that
      # still treats "Rails 8.0" and "Rails 8.1" as overlapping.
      RESTORE_STOPWORDS = %w[for the and with via of in on to by is are].to_set.freeze
      RESTORE_JACCARD_THRESHOLD = 0.5
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

      # Restore superseded facts in a (subject, predicate) slot that were
      # only superseded because of an obsolete single-value classification.
      # Uses Jaccard-based token overlap to distinguish bug-superseded facts
      # (token-disjoint siblings) from legitimate corrections (overlapping
      # siblings).
      #
      # Refuses to run on predicates still classified as single-value — they
      # should stay superseded by design.
      #
      # Never touches status: "rejected" facts (explicit user decisions).
      #
      # @return [Hash] {inspected, restored, skipped_ambiguous, skipped_rejected, decisions}
      def restore_multi_value_supersessions(predicate:, dry_run: false)
        if ClaudeMemory::Resolve::PredicatePolicy.single?(predicate)
          raise ArgumentError, "Predicate '#{predicate}' is still classified single-value; refusing to restore"
        end

        result = {inspected: 0, restored: 0, skipped_ambiguous: 0, skipped_rejected: 0, decisions: []}

        rows_by_subject = @store.facts
          .where(predicate: predicate)
          .exclude(status: "rejected")
          .select(:id, :subject_entity_id, :object_literal, :status)
          .all
          .group_by { |r| r[:subject_entity_id] }

        rejected_by_subject = @store.facts
          .where(predicate: predicate, status: "rejected")
          .select(:id, :subject_entity_id, :object_literal)
          .all
          .group_by { |r| r[:subject_entity_id] }

        @store.db.transaction do
          rows_by_subject.each do |subject_id, rows|
            rejected_rows = rejected_by_subject[subject_id] || []
            siblings = rows + rejected_rows

            rows.each do |candidate|
              next unless candidate[:status] == "superseded"
              result[:inspected] += 1

              candidate_tokens = restore_tokenize(candidate[:object_literal])
              ambiguous_against = find_overlapping_siblings(candidate, siblings, candidate_tokens)

              if ambiguous_against.empty?
                result[:restored] += 1
                result[:decisions] << {
                  subject_entity_id: subject_id,
                  fact_id: candidate[:id],
                  object: candidate[:object_literal],
                  action: :restore
                }
                restore_fact!(candidate[:id]) unless dry_run
              else
                result[:skipped_ambiguous] += 1
                result[:decisions] << {
                  subject_entity_id: subject_id,
                  fact_id: candidate[:id],
                  object: candidate[:object_literal],
                  action: :skip_ambiguous,
                  overlaps_with: ambiguous_against.map { |s| s[:object_literal] }
                }
              end
            end
          end
        end

        result
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

      def restore_tokenize(text)
        return Set.new if text.nil?
        text.downcase
          .scan(/[a-z0-9]+/)
          .reject { |t| t.length <= 2 || RESTORE_STOPWORDS.include?(t) }
          .to_set
      end

      def restore_jaccard(a, b)
        return 0.0 if a.empty? && b.empty?
        intersection = (a & b).size
        union = (a | b).size
        return 0.0 if union.zero?
        intersection.to_f / union
      end

      def find_overlapping_siblings(candidate, siblings, candidate_tokens)
        siblings.select do |other|
          next false if other[:id] == candidate[:id]
          other_tokens = restore_tokenize(other[:object_literal])
          restore_jaccard(candidate_tokens, other_tokens) >= RESTORE_JACCARD_THRESHOLD
        end
      end

      def restore_fact!(fact_id)
        @store.facts.where(id: fact_id).update(status: "active", valid_to: nil)
        @store.fact_links.where(to_fact_id: fact_id, link_type: "supersedes").delete
      end

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
