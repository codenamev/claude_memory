# frozen_string_literal: true

module ClaudeMemory
  module Observe
    # Pure greedy clustering for observation dedup. Given active observation
    # rows already scoped to one scope, plus a similarity matcher, it decides
    # which near-duplicates fold into which keeper — with zero I/O. The
    # Reflector's imperative shell applies the returned plan against the store.
    #
    # Separating the decision (this class) from the side effects (the store
    # writes) lets the clustering algorithm be unit-tested in-memory without a
    # database.
    class DedupPlanner
      # One fold operation: `loser_id`'s sightings roll into `keeper_id`.
      Fold = Struct.new(:keeper_id, :loser_id, :corroboration)

      def initialize(matcher)
        @matcher = matcher
      end

      # Greedy clustering within one scope: the newest observation in a cluster
      # is the keeper; older near-duplicates fold into it. O(n²) matcher calls,
      # but n is bounded (#74 cut the inflow; the Reflector's TTL pass bounds
      # the tail).
      #
      # @param rows [Array<Hash>] active observations in a single scope
      # @return [Array<Fold>] fold operations, in application order
      def plan(rows)
        return [] if rows.size < 2

        ordered = rows.sort_by { |r| [r[:observed_at].to_s, r[:id]] }.reverse
        folded = {}
        folds = []

        ordered.each do |keeper|
          next if folded[keeper[:id]]

          ordered.each do |other|
            next if other[:id] == keeper[:id] || folded[other[:id]]
            next unless @matcher.similar?(keeper[:body], other[:body])

            # A duplicate IS a repeated sighting, so its corroboration folds
            # into the keeper (the signal the promotion gate keys off).
            folds << Fold.new(
              keeper_id: keeper[:id],
              loser_id: other[:id],
              corroboration: other[:corroboration_count] || 1
            )
            folded[other[:id]] = true
          end

          folded[keeper[:id]] = true
        end

        folds
      end
    end
  end
end
