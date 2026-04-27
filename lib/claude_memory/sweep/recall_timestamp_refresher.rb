# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Sweep
    # Path B for #35 access-based staleness — sweep-derived rather than
    # per-recall written. Scans activity_events from both stores, projects
    # the most recent recall/context-injection touch per (scope, fact_id),
    # and bulk-updates facts.last_recalled_at across both DBs.
    #
    # Cross-DB by design: project DBs record activity_events for both
    # project and global facts (a recall fired from a project context that
    # returns global facts is logged in the project DB), so a per-store
    # refresh would silently miss global facts entirely.
    #
    # Lookback bounds keep the scan O(window), not O(history).
    class RecallTimestampRefresher
      DEFAULT_LOOKBACK_DAYS = 90
      RECALL_EVENT_TYPES = %w[recall hook_context].freeze

      def initialize(manager, lookback_days: DEFAULT_LOOKBACK_DAYS)
        @manager = manager
        @lookback_days = lookback_days
      end

      # @return [Hash] {project: Int, global: Int} — count of facts updated per scope.
      def refresh!
        cutoff = (Time.now.utc - @lookback_days * 86_400).iso8601
        latest = collect_latest_per_fact(cutoff)
        apply_to_stores(latest)
      end

      private

      # Scans every activity_events table available to the manager and
      # returns {[scope, fact_id] => latest_occurred_at}.
      def collect_latest_per_fact(cutoff)
        latest = {}
        %w[project global].each do |source|
          store = @manager.store_if_exists(source)
          next unless store
          rows = store.activity_events
            .where(event_type: RECALL_EVENT_TYPES)
            .where { occurred_at >= cutoff }
            .select(:occurred_at, :detail_json)
            .all
          rows.each do |row|
            details = parse_details(row[:detail_json])
            scoped = Dashboard::ScopedFactResolver.scoped_ids_from_details(details)
            scoped.each do |scope, ids|
              ids.each do |fact_id|
                key = [scope.to_s, fact_id]
                existing = latest[key]
                latest[key] = row[:occurred_at] if existing.nil? || row[:occurred_at] > existing
              end
            end
          end
        end
        latest
      end

      def parse_details(detail_json)
        return {} if detail_json.nil? || detail_json.empty?
        JSON.parse(detail_json, symbolize_names: true)
      rescue JSON::ParserError
        {}
      end

      def apply_to_stores(latest)
        counts = {project: 0, global: 0}
        latest.group_by { |(scope, _id), _ts| scope }.each do |scope, entries|
          store = @manager.store_if_exists(scope)
          next unless store
          entries.each do |((_scope, fact_id), ts)|
            counts[scope.to_sym] += store.facts.where(id: fact_id).update(last_recalled_at: ts)
          end
        end
        counts
      end
    end
  end
end
