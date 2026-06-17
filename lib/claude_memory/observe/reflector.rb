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
    #   - dedupe: collapse near-identical active observations (same scope,
    #     normalized body) into the newest, linking losers via consolidated_into.
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
      Result = Struct.new(:deduped, :expired, keyword_init: true) do
        def total
          deduped + expired
        end
      end

      def initialize(store, info_ttl_days: DEFAULT_INFO_TTL_DAYS)
        @store = store
        @info_ttl_days = info_ttl_days
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
        merged = 0

        active.group_by { |o| [o[:scope], normalize(o[:body])] }.each_value do |rows|
          next if rows.size < 2

          keeper = rows.max_by { |r| [r[:observed_at].to_s, r[:id]] }
          rows.each do |loser|
            next if loser[:id] == keeper[:id]
            @store.tombstone_observation(loser[:id], into_id: keeper[:id])
            merged += 1
          end
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

      def normalize(body)
        body.to_s.downcase.gsub(/\s+/, " ").strip
      end
    end
  end
end
