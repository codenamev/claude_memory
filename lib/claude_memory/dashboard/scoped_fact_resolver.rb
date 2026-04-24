# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Resolves fact IDs from recall/context-injection event details back to
    # the facts they actually referenced, respecting scope. Fact IDs
    # autoincrement per-DB, so a bare numeric ID is ambiguous — project fact
    # #1 and global fact #1 are different facts.
    #
    # Reads in priority order:
    #
    # 1. top_facts_by_scope (new, authoritative) — already scope-tagged
    # 2. top_fact_ids + single-scope results_by_scope — historical events
    #    from before the fix; if the recall only touched one scope, every
    #    ID must belong to that scope
    # 3. top_fact_ids alone — last-resort fallback; default to project
    #
    # Every reader in the dashboard goes through this so the scope bug
    # can't reappear in one spot while being fixed in another.
    module ScopedFactResolver
      module_function

      # Normalize event details into a {scope => [ids]} hash. Returns an
      # empty hash when no fact-ID references are present.
      #
      # @param details [Hash] parsed detail_json from an activity_event row
      # @return [Hash{String => Array<Integer>}]
      def scoped_ids_from_details(details)
        return {} unless details.is_a?(Hash)
        authoritative = extract_top_facts_by_scope(details)
        return authoritative if authoritative.any?

        flat_ids = Array(details[:top_fact_ids] || details["top_fact_ids"]).map(&:to_i).reject(&:zero?)
        return {} if flat_ids.empty?

        scope = single_scope_from(details[:results_by_scope] || details["results_by_scope"])
        {scope || "project" => flat_ids}
      end

      # Resolve an entire {scope => [ids]} hash into ordered fact rows.
      # Preserves the input order per scope so "top fact" ordering
      # survives the round trip.
      #
      # @param manager [Store::StoreManager]
      # @return [Array<Hash>] presenter-ready fact summaries with :source
      def resolve(manager, scoped_ids)
        return [] if scoped_ids.nil? || scoped_ids.empty?
        results = []
        scoped_ids.each do |scope, ids|
          next if ids.nil? || ids.empty?
          store = manager.store_if_exists(scope.to_s)
          next unless store
          rows = store.facts.where(id: ids.map(&:to_i)).all
          next if rows.empty?
          index = ids.each_with_index.to_h { |id, i| [id.to_i, i] }
          rows.sort_by! { |r| index[r[:id]] || Float::INFINITY }
          presented = FactPresenter.new(store).list_summary(rows)
          presented.each { |f| results << f.merge(source: scope.to_s) }
        end
        results
      rescue Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("ScopedFactResolver#resolve failed: #{e.message}")
        []
      end

      # Flat list of unique scoped pairs — handy for counting unique facts
      # referenced across a set of events.
      #
      # @return [Array<Array(String, Integer)>] [[scope, id], ...]
      def flat_pairs(scoped_ids)
        return [] if scoped_ids.nil? || scoped_ids.empty?
        scoped_ids.flat_map { |scope, ids| ids.map { |id| [scope.to_s, id.to_i] } }.uniq
      end

      def extract_top_facts_by_scope(details)
        raw = details[:top_facts_by_scope] || details["top_facts_by_scope"]
        return {} unless raw.is_a?(Hash)
        raw.each_with_object({}) do |(scope, ids), acc|
          cleaned = Array(ids).map(&:to_i).reject(&:zero?)
          acc[scope.to_s] = cleaned unless cleaned.empty?
        end
      end

      # If a recall's results came from exactly one scope, every fact ID
      # must belong to that scope. Returns the scope name, or nil when the
      # recall touched multiple scopes (can't disambiguate) or none.
      def single_scope_from(results_by_scope)
        return nil unless results_by_scope.is_a?(Hash)
        scopes_with_hits = results_by_scope.reject { |_, count| count.nil? || count.zero? }.keys
        return nil unless scopes_with_hits.size == 1
        scopes_with_hits.first.to_s
      end
    end
  end
end
