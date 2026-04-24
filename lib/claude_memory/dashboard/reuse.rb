# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Tracks which facts Claude actually *uses* in sessions — the ROI number.
    # A fact that was taught once and then cited 10 times over the following
    # month is earning its keep. A fact that's been sitting active for six
    # months with zero recalls is just database weight.
    #
    # Counts both recall events (explicit memory.recall calls) and context
    # injections (hook_context emitted_fact_ids), because both represent
    # memory shaping what Claude sees.
    class Reuse
      DEFAULT_WINDOW_SECONDS = 7 * 86_400
      DEFAULT_LIMIT = 10

      COUNTING_EVENT_TYPES = %w[recall hook_context].freeze

      def initialize(manager)
        @manager = manager
      end

      # @param params [Hash]
      #   "since" — ISO 8601 cutoff, defaults to 7 days ago
      #   "limit" — max facts to return (default 10)
      def top(params = {})
        store = @manager.default_store(prefer: :project)
        return {facts: [], window: default_window, event_count: 0} unless store

        since = params["since"] || (Time.now.utc - DEFAULT_WINDOW_SECONDS).iso8601
        limit = (params["limit"] || DEFAULT_LIMIT).to_i.clamp(1, 50)

        event_rows = store.activity_events
          .where(event_type: COUNTING_EVENT_TYPES)
          .where(status: "success")
          .where { occurred_at >= since }
          .select(:id, :event_type, :occurred_at, :detail_json)
          .all

        # Count by (scope, id) pair. Project fact #5 and global fact #5
        # are different facts — never merge their counts.
        counts = Hash.new(0)
        last_seen = {}
        event_rows.each do |row|
          details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
          scoped = ScopedFactResolver.scoped_ids_from_details(details)
          ScopedFactResolver.flat_pairs(scoped).each do |pair|
            counts[pair] += 1
            last_seen[pair] = [last_seen[pair], row[:occurred_at]].compact.max
          end
        end

        return {facts: [], window: {since: since}, event_count: event_rows.size} if counts.empty?

        top_pairs = counts.sort_by { |_, c| -c }.first(limit).to_h.keys

        # Resolve each (scope, id) in the correct DB, preserving recall
        # count + last_recalled metadata.
        facts = []
        top_pairs.group_by(&:first).each do |scope, pairs|
          s = @manager.store_if_exists(scope)
          next unless s
          ids = pairs.map(&:last)
          rows = s.facts.where(id: ids, status: "active").all
          next if rows.empty?
          presented = FactPresenter.new(s).list_summary(rows)
          rows.zip(presented).each do |raw, p|
            pair = [scope, raw[:id]]
            facts << p.merge(
              source: scope,
              recall_count: counts[pair],
              last_recalled_at: last_seen[pair],
              last_recalled_ago: Core::RelativeTime.format(last_seen[pair])
            )
          end
        end

        facts.sort_by! { |f| -f[:recall_count] }

        {
          window: {since: since},
          event_count: event_rows.size,
          facts: facts.first(limit)
        }
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("Reuse#top failed: #{e.message}")
        {facts: [], window: default_window, event_count: 0, error: e.message}
      end

      private

      def default_window
        {since: (Time.now.utc - DEFAULT_WINDOW_SECONDS).iso8601}
      end
    end
  end
end
