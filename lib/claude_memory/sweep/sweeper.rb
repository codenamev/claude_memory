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
        @store.execute(
          "UPDATE facts SET status = 'expired' WHERE status = 'proposed' AND created_at < ?",
          [cutoff]
        )
        @stats[:proposed_facts_expired] = @store.db.changes
      end

      def expire_disputed_facts
        cutoff = (Time.now - @config[:disputed_fact_ttl_days] * 86400).utc.iso8601
        @store.execute(
          "UPDATE facts SET status = 'expired' WHERE status = 'disputed' AND created_at < ?",
          [cutoff]
        )
        @stats[:disputed_facts_expired] = @store.db.changes
      end

      def prune_orphaned_provenance
        @store.execute(<<~SQL)
          DELETE FROM provenance 
          WHERE fact_id NOT IN (SELECT id FROM facts)
        SQL
        @stats[:orphaned_provenance_deleted] = @store.db.changes
      end

      def prune_old_content
        cutoff = (Time.now - @config[:content_retention_days] * 86400).utc.iso8601
        @store.execute(<<~SQL, [cutoff])
          DELETE FROM content_items 
          WHERE ingested_at < ? 
          AND id NOT IN (SELECT content_item_id FROM provenance WHERE content_item_id IS NOT NULL)
        SQL
        @stats[:old_content_pruned] = @store.db.changes
      end
    end
  end
end
