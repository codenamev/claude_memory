# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Conflicts resource for the dashboard API. Owns list/detail/reject
    # across both scopes (global + project) and keeps them disjoint — a
    # conflict in one store can never reference a fact in the other.
    #
    # List results are deduplicated at the display layer by
    # (source, predicate, normalized(object_a, object_b), status). Each group
    # carries a `group_size` so the UI can label "sqlite vs postgres (×11)"
    # instead of surfacing 11 rows that resolve identically. `counts` reflects
    # the distinct count; `raw_counts` preserves the underlying row totals for
    # the Advanced drawer.
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

        groups = group_rows(rows)
        groups.sort_by! { |g| -parse_timestamp(g[:representative][:detected_at]) }

        {
          total: groups.size,
          limit: limit,
          offset: offset,
          scope: scope,
          status: status_filter,
          counts: counts_across_scopes,
          raw_counts: raw_counts_across_scopes,
          conflicts: Array(groups[offset, limit]).map { |g| serialize_group(g) }
        }
      end

      # Count distinct open conflicts per scope (after deduplication). Used by
      # Trust#needs_review so the sidebar backlog reflects distinct pairs
      # rather than duplicated rows from pre-dedupe history.
      def distinct_open_counts
        counts = {project: 0, global: 0}
        %w[project global].each do |scope|
          store = @manager.store_if_exists(scope)
          next unless store
          rows = store.conflicts.where(status: "open").all
            .map { |r| r.merge(source: scope, store: store) }
          counts[scope.to_sym] = group_rows(rows).size
        end
        counts.merge(total: counts.values.sum)
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
      # a single transaction, so duplicate rows collapse automatically.
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

      # Bulk-reject every disputed fact that's in open conflict against a
      # single "keeper" fact. Resolves the distiller-hallucination pattern
      # where one correct fact (e.g. uses_database=sqlite) accumulates many
      # contradicting candidates (postgresql, mysql, redis, ...). For each
      # open conflict where keeper_fact_id is on either side, the fact on
      # the OTHER side is rejected; SQLiteStore#reject_fact cascade-resolves
      # the conflict inside its own transaction.
      #
      # @return [Hash] {rejected_fact_ids:, conflicts_resolved:}
      def reject_similar(keeper_fact_id, reason: nil, scope: "project")
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = @manager.store_if_exists(scope)
        return {error: "#{scope} store not available"} unless store

        keeper_id = keeper_fact_id.to_i
        rows = store.conflicts
          .where(status: "open")
          .where(Sequel.|({fact_a_id: keeper_id}, {fact_b_id: keeper_id}))
          .all

        return {success: true, keeper_fact_id: keeper_id, rejected_fact_ids: [], conflicts_resolved: 0} if rows.empty?

        rejected = []
        total_resolved = 0
        rows.each do |row|
          loser_id = (row[:fact_a_id] == keeper_id) ? row[:fact_b_id] : row[:fact_a_id]
          next if rejected.include?(loser_id)
          result = store.reject_fact(loser_id, reason: reason)
          rejected << loser_id
          total_resolved += result[:conflicts_resolved] || 0
        end

        {
          success: true,
          keeper_fact_id: keeper_id,
          rejected_fact_ids: rejected,
          conflicts_resolved: total_resolved,
          scope: scope
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
          %w[open resolved].each do |status|
            rows = store.conflicts.where(status: status).all
              .map { |r| r.merge(source: source.to_s, store: store) }
            distinct = group_rows(rows).size
            counts[source][status.to_sym] = distinct
            counts[source][:total] += distinct
          end
        end
        counts
      end

      def raw_counts_across_scopes
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

      # Group conflict rows by (source, predicate, normalized(objects), status)
      # so pre-dedupe historical duplicates collapse into one display row.
      # Returns [{representative:, members:, facts:}...] — `representative` is
      # the most recently detected row in the group; `members` is all raw rows;
      # `facts` maps fact_id → facts-table row for the representative's two
      # sides (batched to avoid N+1).
      def group_rows(rows)
        return [] if rows.empty?

        facts_by_source = load_facts_for_rows(rows)

        groups = {}
        rows.each do |row|
          store_facts = facts_by_source[row[:source]] || {}
          fact_a = store_facts[row[:fact_a_id]]
          fact_b = store_facts[row[:fact_b_id]]
          key = grouping_key(row, fact_a, fact_b)
          groups[key] ||= {members: [], facts: {}}
          groups[key][:members] << row
          groups[key][:facts][row[:fact_a_id]] ||= fact_a if fact_a
          groups[key][:facts][row[:fact_b_id]] ||= fact_b if fact_b
        end

        groups.values.map do |g|
          sorted = g[:members].sort_by { |r| -parse_timestamp(r[:detected_at]) }
          {representative: sorted.first, members: g[:members], facts: g[:facts]}
        end
      end

      def load_facts_for_rows(rows)
        by_source = {}
        rows.group_by { |r| [r[:source], r[:store]] }.each do |(source, store), group|
          ids = group.flat_map { |r| [r[:fact_a_id], r[:fact_b_id]] }.compact.uniq
          by_source[source] = ids.empty? ? {} : store.facts.where(id: ids).as_hash(:id)
        end
        by_source
      end

      def grouping_key(row, fact_a, fact_b)
        predicate = fact_a&.dig(:predicate) || fact_b&.dig(:predicate) || "?"
        objects = [normalize_object(fact_a), normalize_object(fact_b)].sort
        [row[:source], row[:status], predicate, *objects]
      end

      def normalize_object(fact)
        return "" unless fact
        (fact[:object_literal] || "").to_s.downcase.strip.gsub(/\s+/, " ")
      end

      def serialize_group(group)
        row = group[:representative]
        store = row[:store]
        presenter = FactPresenter.new(store)
        fact_a = group[:facts][row[:fact_a_id]] || store.facts.where(id: row[:fact_a_id]).first
        fact_b = group[:facts][row[:fact_b_id]] || store.facts.where(id: row[:fact_b_id]).first

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
          source: row[:source],
          group_size: group[:members].size,
          group_member_ids: group[:members].map { |m| m[:id] }
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
