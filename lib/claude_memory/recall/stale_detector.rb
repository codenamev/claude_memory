# frozen_string_literal: true

module ClaudeMemory
  class Recall
    # #35 access-based staleness — read-only query layer over the
    # last_recalled_at column populated by Sweep::RecallTimestampRefresher.
    #
    # An active fact is "stale" when:
    # - It hasn't been recalled or context-injected within `threshold_days`
    #   (last_recalled_at < cutoff OR last_recalled_at is NULL), AND
    # - It was created before the cutoff too — freshly extracted facts
    #   aren't dead weight, they just haven't had a chance to be used.
    #
    # No auto-deletion. The point is to surface a count and a list to the
    # user so they can review and reject; the sweeper never acts on this.
    module StaleDetector
      module_function

      # @param manager [Store::StoreManager]
      # @param threshold_days [Integer] grace window in days
      # @param limit [Integer] max rows per scope (0 = unlimited)
      # @return [Hash] {project: [...], global: [...], total: Int}
      def stale_facts(manager, threshold_days:, limit: 50)
        cutoff = (Time.now.utc - threshold_days * 86_400).iso8601
        result = {project: [], global: [], total: 0}

        %w[project global].each do |scope|
          store = manager.store_if_exists(scope)
          next unless store
          rows = stale_rows_for(store, cutoff, limit)
          result[scope.to_sym] = rows
          result[:total] += rows.size
        end

        result
      end

      # Scope-agnostic count helper for the dashboard sidebar. Avoids
      # materializing rows when only a count is needed.
      #
      # @return [Integer] total stale facts across both stores
      def stale_count(manager, threshold_days:)
        cutoff = (Time.now.utc - threshold_days * 86_400).iso8601
        count = 0
        %w[project global].each do |scope|
          store = manager.store_if_exists(scope)
          next unless store
          count += stale_dataset(store, cutoff).count
        end
        count
      end

      def stale_dataset(store, cutoff)
        store.facts
          .where(status: "active")
          .where { created_at < cutoff }
          .where { (last_recalled_at < cutoff) | {last_recalled_at: nil} }
      end

      def stale_rows_for(store, cutoff, limit)
        ds = stale_dataset(store, cutoff).order(Sequel.asc(:last_recalled_at)).order_append(:created_at)
        ds = ds.limit(limit) if limit > 0
        ds.all
      end
    end
  end
end
