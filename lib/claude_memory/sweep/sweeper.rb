# frozen_string_literal: true

module ClaudeMemory
  module Sweep
    class Sweeper
      DEFAULT_CONFIG = {
        proposed_fact_ttl_days: 14,
        disputed_fact_ttl_days: 30,
        content_retention_days: 30,
        mcp_tool_call_retention_days: 90,
        otel_metric_retention_days: 30,
        otel_event_retention_days: 14,
        otel_trace_retention_days: 7,
        observation_info_ttl_days: 30,
        default_budget_seconds: 5
      }.freeze

      # Three-level escalation ensures sweep always makes progress.
      # Source: lossless-claw three-level escalation pattern
      ESCALATION_LEVELS = %i[normal aggressive fallback].freeze

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
          old_content_pruned: 0,
          mcp_tool_calls_pruned: 0,
          escalation_level: :normal
        }

        maintenance = build_maintenance(:normal)

        run_if_within_budget { @stats[:proposed_facts_expired] = maintenance.expire_proposed_facts }
        run_if_within_budget { @stats[:disputed_facts_expired] = maintenance.expire_disputed_facts }
        run_if_within_budget { @stats[:multi_value_facts_merged] = maintenance.dedupe_multi_value_facts }
        run_if_within_budget { @stats[:scope_leakage_fixed] = maintenance.fix_scope_leakage }
        run_if_within_budget { @stats[:orphaned_provenance_deleted] = maintenance.prune_orphaned_provenance }
        run_if_within_budget { @stats[:old_content_pruned] = maintenance.prune_old_content }
        run_if_within_budget { @stats[:mcp_tool_calls_pruned] = maintenance.prune_old_mcp_tool_calls }
        run_if_within_budget { @stats[:otel_metrics_pruned] = maintenance.prune_old_otel_metrics }
        run_if_within_budget { @stats[:otel_events_pruned] = maintenance.prune_old_otel_events }
        run_if_within_budget { @stats[:otel_traces_pruned] = maintenance.prune_old_otel_traces }
        run_if_within_budget { @stats[:vec_backfilled] = maintenance.backfill_vec_index }
        run_if_within_budget { @stats[:vec_cleaned] = maintenance.cleanup_vec_expired }
        run_if_within_budget do
          reflection = maintenance.reflect_observations
          @stats[:observations_deduped] = reflection[:deduped]
          @stats[:observations_expired] = reflection[:expired]
        end
        run_if_within_budget { @stats[:fts_rank_repaired] = maintenance.repair_fts_rank }
        run_if_within_budget { @stats[:wal_checkpointed] = maintenance.checkpoint_wal }

        @stats[:elapsed_seconds] = Time.now - @start_time
        @stats[:budget_honored] = @stats[:elapsed_seconds] <= budget
        ClaudeMemory.logger.info("sweep",
          message: "Sweep complete",
          elapsed_seconds: @stats[:elapsed_seconds].round(3),
          budget_honored: @stats[:budget_honored],
          escalation_level: @stats[:escalation_level],
          proposed_expired: @stats[:proposed_facts_expired],
          disputed_expired: @stats[:disputed_facts_expired])
        @stats
      end

      # Run sweep with escalation: if normal sweep makes no progress,
      # escalate to aggressive (halved TTLs), then fallback (force-expire oldest).
      # Returns stats hash with :escalation_level indicating which level succeeded.
      #
      # Source: lossless-claw three-level escalation pattern
      def run_with_escalation!(budget_seconds: nil)
        stats = run!(budget_seconds: budget_seconds)
        total = stats[:proposed_facts_expired] + stats[:disputed_facts_expired] +
          stats[:orphaned_provenance_deleted] + stats[:old_content_pruned]

        if total == 0
          # Escalate to aggressive — halved TTLs
          aggressive_maintenance = build_maintenance(:aggressive)
          added = 0
          added += aggressive_maintenance.expire_proposed_facts
          added += aggressive_maintenance.expire_disputed_facts
          added += aggressive_maintenance.prune_old_content

          if added > 0
            stats[:proposed_facts_expired] += added
            stats[:escalation_level] = :aggressive
          else
            # Fallback — force-expire oldest proposed/disputed facts
            fallback_count = force_expire_oldest
            stats[:proposed_facts_expired] += fallback_count
            stats[:escalation_level] = :fallback if fallback_count > 0
          end

          stats[:elapsed_seconds] = Time.now - @start_time
        end

        stats
      end

      private

      def build_maintenance(level)
        config = case level
        when :aggressive
          {
            proposed_fact_ttl_days: @config[:proposed_fact_ttl_days] / 2,
            disputed_fact_ttl_days: @config[:disputed_fact_ttl_days] / 2,
            content_retention_days: @config[:content_retention_days] / 2
          }
        else
          @config.slice(:proposed_fact_ttl_days, :disputed_fact_ttl_days, :content_retention_days, :observation_info_ttl_days)
        end

        Maintenance.new(@store, config: config)
      end

      # Force-expire the oldest proposed or disputed facts regardless of TTL.
      # Guarantees progress when normal and aggressive sweeps find nothing.
      # Limited to 10 facts per invocation for safety.
      def force_expire_oldest(limit: 10)
        oldest_ids = @store.facts
          .where(status: %w[proposed disputed])
          .order(:created_at)
          .limit(limit)
          .select(:id)
          .map { |r| r[:id] }

        return 0 if oldest_ids.empty?

        @store.facts
          .where(id: oldest_ids)
          .update(status: "expired")
      end

      def run_if_within_budget
        return unless within_budget?
        yield
      end

      def within_budget?
        budget = @config[:default_budget_seconds]
        (Time.now - @start_time) < budget
      end
    end
  end
end
