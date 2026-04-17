# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Conflicts resource for the dashboard API. Owns list/detail/reject
    # across both scopes (global + project) and keeps them disjoint — a
    # conflict in one store can never reference a fact in the other.
    #
    # The `counts` field in {#list} is always computed across both scopes
    # regardless of the current filter so the UI can label its
    # Project / Global / All sub-tabs with accurate totals.
    class Conflicts
      DEFAULT_LIMIT = 50

      def initialize(manager)
        @manager = manager
      end

      # @param params [Hash] "scope" (project|global|all), "status"
      #   (open|resolved|all), "limit", "offset"
      def list(params = {})
        scope = params["scope"] || "project"
        status_filter = params["status"] || "open"
        limit = (params["limit"] || DEFAULT_LIMIT).to_i
        offset = (params["offset"] || 0).to_i

        stores = stores_for(scope)
        rows = stores.flat_map { |source, store|
          dataset = store.conflicts
          dataset = dataset.where(status: status_filter) unless status_filter == "all"
          dataset.all.map { |r| r.merge(source: source, store: store) }
        }
        rows.sort_by! { |r| -parse_timestamp(r[:detected_at]) }

        {
          total: rows.size,
          limit: limit,
          offset: offset,
          scope: scope,
          status: status_filter,
          counts: counts_across_scopes,
          conflicts: Array(rows[offset, limit]).map { |r| serialize_row(r) }
        }
      end

      # @param id [Integer, String] conflict row id
      # @param scope [String] "project" or "global" (required — conflicts are scope-local)
      def detail(id, scope)
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = @manager.store_if_exists(scope)
        return {error: "#{scope} store not available"} unless store

        row = store.conflicts.where(id: id.to_i).first
        return {error: "Conflict #{id} not found"} unless row

        presenter = FactPresenter.new(store)
        {
          conflict: {
            id: row[:id],
            status: row[:status],
            detected_at: row[:detected_at],
            detected_ago: Core::RelativeTime.format(row[:detected_at]),
            notes: row[:notes],
            source: scope
          },
          fact_a: presenter.with_provenance(store.facts.where(id: row[:fact_a_id]).first),
          fact_b: presenter.with_provenance(store.facts.where(id: row[:fact_b_id]).first)
        }
      end

      # Rejects one side of a conflict by rejecting its fact. SQLiteStore#reject_fact
      # flips the fact to "rejected" and cascade-resolves associated conflicts in
      # a single transaction, so the conflict's status transitions automatically.
      def reject(id, side:, reason: nil, scope: "project")
        return {error: "Invalid side (must be 'a' or 'b')"} unless %w[a b].include?(side)
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = @manager.store_if_exists(scope)
        return {error: "#{scope} store not available"} unless store

        row = store.conflicts.where(id: id.to_i).first
        return {error: "Conflict #{id} not found"} unless row

        fact_id = (side == "a") ? row[:fact_a_id] : row[:fact_b_id]
        result = store.reject_fact(fact_id, reason: reason)

        {
          success: true,
          conflict_id: id,
          rejected_fact_id: fact_id,
          side: side,
          scope: scope,
          conflicts_resolved: result[:conflicts_resolved]
        }
      end

      private

      def stores_for(scope)
        case scope
        when "project"
          {"project" => @manager.store_if_exists("project")}.compact
        when "global"
          {"global" => @manager.store_if_exists("global")}.compact
        else
          {
            "project" => @manager.store_if_exists("project"),
            "global" => @manager.store_if_exists("global")
          }.compact
        end
      end

      def counts_across_scopes
        counts = {project: {open: 0, resolved: 0, total: 0},
                  global: {open: 0, resolved: 0, total: 0}}
        [:project, :global].each do |source|
          store = @manager.store_if_exists(source.to_s)
          next unless store
          store.conflicts.group_and_count(:status).all.each do |r|
            key = r[:status].to_sym
            counts[source][key] = r[:count] if counts[source].key?(key)
            counts[source][:total] += r[:count]
          end
        end
        counts
      end

      def serialize_row(row)
        store = row[:store]
        presenter = FactPresenter.new(store)
        fact_a = store.facts.where(id: row[:fact_a_id]).first
        fact_b = store.facts.where(id: row[:fact_b_id]).first

        {
          id: row[:id],
          fact_a_id: row[:fact_a_id],
          fact_b_id: row[:fact_b_id],
          fact_a_preview: presenter.preview(fact_a),
          fact_b_preview: presenter.preview(fact_b),
          status: row[:status],
          detected_at: row[:detected_at],
          detected_ago: Core::RelativeTime.format(row[:detected_at]),
          notes: row[:notes],
          source: row[:source]
        }
      end

      def parse_timestamp(value)
        Time.parse(value.to_s).to_i
      rescue ArgumentError, TypeError
        0
      end
    end
  end
end
