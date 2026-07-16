# frozen_string_literal: true

module ClaudeMemory
  module Observe
    # Deterministic, free (no LLM) Reflector for the episodic observation log.
    #
    # Runs inside Sweep, which fires on PreCompact and SessionEnd — Claude
    # Code's context-pressure lifecycle events. That is the analog of Mastra's
    # token-threshold-triggered reflection: "reflect when memory gets big" maps
    # onto "reflect when the session is about to compact", without a wall-clock
    # timer (Claude Code has no cron hook) and without extra API cost.
    #
    # Two passes, both provenance-preserving (tombstone, never hard-delete):
    #   - dedupe: collapse near-duplicate active observations (same scope) into
    #     the newest, linking losers via consolidated_into. Similarity is decided
    #     by an injected matcher (default: lexical token-overlap, #73) so the
    #     promotion gate can actually accumulate corroboration — exact-string
    #     matching never folded varied wording, leaving every observation at
    #     corroboration 1 (the 2026-06-23 audit finding).
    #   - expire_stale_info: retire info-level (🟢 / priority 3) observations
    #     older than the TTL to bound context size. Important (🔴) and maybe
    #     (🟡) are never expired — only the lowest-signal tier ages out.
    #
    # Semantic consolidation ("combine related items, surface patterns") is
    # deliberately NOT here — it needs the LLM and lands in the Phase-4
    # Claude-as-reflector pass. This pass is pure Ruby so it can run shell-side
    # in the sweep hook for free.
    class Reflector
      DEFAULT_INFO_TTL_DAYS = 30

      # @return [Struct] counts from one reflection pass
      Result = Struct.new(:deduped, :expired) do
        def total
          deduped + expired
        end
      end

      def initialize(store, info_ttl_days: DEFAULT_INFO_TTL_DAYS, matcher: TokenOverlapMatcher.new, clock: Time)
        @store = store
        @info_ttl_days = info_ttl_days
        @clock = clock
        @planner = DedupPlanner.new(matcher)
      end

      # @return [Result] number of observations deduped and expired
      def reflect!
        deduped = 0
        expired = 0
        # Retryable transaction: reflection runs in the sweep hook, which races
        # the ingest hook for the WAL writer (the documented contention gotcha).
        # transaction_with_retry retries the whole transaction on SQLITE_BUSY —
        # the individual mutators must NOT be wrapped, since retrying a single
        # statement inside an open transaction can't clear the busy lock.
        @store.transaction_with_retry do
          deduped = dedupe
          expired = expire_stale_info
        end
        Result.new(deduped: deduped, expired: expired)
      end

      private

      # Plan folds per scope with the pure DedupPlanner (no I/O), then apply
      # them: fold the loser's sightings into the keeper before tombstoning it
      # so corroboration survives consolidation and can cross the promotion
      # threshold.
      def dedupe
        active = @store.observations.where(status: "active").order(:id).all
        folds = active.group_by { |o| o[:scope] }
          .flat_map { |_scope, rows| @planner.plan(rows) }

        folds.each do |fold|
          @store.increment_corroboration(fold.keeper_id, by: fold.corroboration)
          @store.tombstone_observation(fold.loser_id, into_id: fold.keeper_id)
        end
        folds.size
      end

      def expire_stale_info
        cutoff = (@clock.now - @info_ttl_days * 86400).utc.iso8601
        ids = @store.observations
          .where(status: "active", priority: Domain::Observation::INFO)
          .where { observed_at < cutoff }
          .select(:id)
          .map { |r| r[:id] }

        ids.each { |id| @store.expire_observation(id) }
        ids.size
      end
    end
  end
end
