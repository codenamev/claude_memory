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

      def initialize(store, info_ttl_days: DEFAULT_INFO_TTL_DAYS, matcher: TokenOverlapMatcher.new)
        @store = store
        @info_ttl_days = info_ttl_days
        @matcher = matcher
      end

      # @return [Result] number of observations deduped and expired
      def reflect!
        deduped = 0
        expired = 0
        @store.db.transaction do
          deduped = dedupe
          expired = expire_stale_info
        end
        Result.new(deduped: deduped, expired: expired)
      end

      private

      def dedupe
        active = @store.observations.where(status: "active").order(:id).all
        active.group_by { |o| o[:scope] }.sum { |_scope, rows| dedupe_scope(rows) }
      end

      # Greedy clustering within one scope: the newest observation in a cluster
      # is the keeper; older near-duplicates fold into it. O(n²) matcher calls,
      # but n is bounded (#74 cut the inflow; expire_stale_info bounds the tail).
      def dedupe_scope(rows)
        return 0 if rows.size < 2

        ordered = rows.sort_by { |r| [r[:observed_at].to_s, r[:id]] }.reverse
        folded = {}
        merged = 0

        ordered.each do |keeper|
          next if folded[keeper[:id]]

          ordered.each do |other|
            next if other[:id] == keeper[:id] || folded[other[:id]]
            next unless @matcher.similar?(keeper[:body], other[:body])

            # Fold the duplicate's sightings into the keeper before tombstoning
            # so corroboration survives consolidation and can cross the promotion
            # threshold. A duplicate IS a repeated sighting.
            @store.increment_corroboration(keeper[:id], by: other[:corroboration_count] || 1)
            @store.tombstone_observation(other[:id], into_id: keeper[:id])
            folded[other[:id]] = true
            merged += 1
          end

          folded[keeper[:id]] = true
        end

        merged
      end

      def expire_stale_info
        cutoff = (Time.now - @info_ttl_days * 86400).utc.iso8601
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
