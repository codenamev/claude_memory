# frozen_string_literal: true

module ClaudeMemory
  module Sweep
    class Sweeper
      DEFAULT_CONFIG = {
        proposed_fact_ttl_days: 14,
        disputed_fact_ttl_days: 30,
        content_retention_days: 30,
        default_budget_seconds: 5
      }.freeze

      def initialize(store, config: {})
        @store = store
        @config = DEFAULT_CONFIG.merge(config)
        @start_time = nil
        @stats = nil
      end

      def run!(budget_seconds: nil)
        budget = budget_seconds || @config[:default_budget_seconds]
        @start_time = Time.now
        @stats = {
          proposed_facts_expired: 0,
          disputed_facts_expired: 0,
          orphaned_provenance_deleted: 0,
          old_content_pruned: 0
        }

        expire_proposed_facts if within_budget?
        expire_disputed_facts if within_budget?
        prune_orphaned_provenance if within_budget?
        prune_old_content if within_budget?
        checkpoint_wal if within_budget?

        @stats[:elapsed_seconds] = Time.now - @start_time
        @stats[:budget_honored] = @stats[:elapsed_seconds] <= budget
        @stats
      end

      private

      def within_budget?
        budget = @config[:default_budget_seconds]
        (Time.now - @start_time) < budget
      end

      def expire_proposed_facts
        cutoff = (Time.now - @config[:proposed_fact_ttl_days] * 86400).utc.iso8601
        @stats[:proposed_facts_expired] = @store.facts
          .where(status: "proposed")
          .where { created_at < cutoff }
          .update(status: "expired")
      end

      def expire_disputed_facts
        cutoff = (Time.now - @config[:disputed_fact_ttl_days] * 86400).utc.iso8601
        @stats[:disputed_facts_expired] = @store.facts
          .where(status: "disputed")
          .where { created_at < cutoff }
          .update(status: "expired")
      end

      def prune_orphaned_provenance
        fact_ids = @store.facts.select(:id)
        @stats[:orphaned_provenance_deleted] = @store.provenance
          .exclude(fact_id: fact_ids)
          .delete
      end

      def prune_old_content
        cutoff = (Time.now - @config[:content_retention_days] * 86400).utc.iso8601
        referenced_ids = @store.provenance.exclude(content_item_id: nil).select(:content_item_id)
        @stats[:old_content_pruned] = @store.content_items
          .where { ingested_at < cutoff }
          .exclude(id: referenced_ids)
          .delete
      end

      def checkpoint_wal
        @store.checkpoint_wal
        @stats[:wal_checkpointed] = true
      end
    end
  end
end
