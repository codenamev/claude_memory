# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Flags subjects holding more than one active fact on a predicate that
      # PredicatePolicy doesn't know. Novel predicates default to multi-valued,
      # so Resolver, StalenessAnnotator, and HistoricalCleanup never supersede
      # them: a v1 and v2 of the same fact both stay active with no conflict
      # raised (issue #21). Some novel predicates are genuinely multi-valued, so
      # this is a warning to look, not an error.
      class NovelPredicateCheck
        MAX_EXAMPLES = 5

        def initialize(db_path, label)
          @db_path = db_path
          @label = label
        end

        def call
          return skip_result unless File.exist?(@db_path)

          store = Store::SQLiteStore.new(@db_path)
          begin
            groups = multi_active_novel(store)
            groups.empty? ? ok_result : warning_result(groups)
          ensure
            store.close
          end
        rescue => e
          # No facts table (fresh or foreign DB) is not this check's concern.
          {status: :ok, label: check_label, message: "#{@label} novel predicates check skipped: #{e.message}", details: {}}
        end

        private

        def multi_active_novel(store)
          store.facts
            .where(status: "active")
            .exclude(predicate: Resolve::PredicatePolicy.known_predicates)
            .group_and_count(:subject_entity_id, :predicate)
            .having { count.function.* > 1 }
            .order(Sequel.desc(:count))
            .all
        end

        def check_label = "#{@label}_novel_predicates"

        def ok_result
          {status: :ok, label: check_label, message: "#{@label} novel predicates: no subject has multiple active values", details: {}}
        end

        def warning_result(groups)
          examples = groups.first(MAX_EXAMPLES).map { |g| "#{g[:predicate]} (subject #{g[:subject_entity_id]}: #{g[:count]} active)" }
          {
            status: :warning,
            label: check_label,
            message: "#{@label} has #{groups.size} subject/predicate pair(s) with multiple active facts on predicates PredicatePolicy doesn't know; " \
                     "these never supersede, so an old value may still be active. Run 'claude-memory census' to review.",
            details: {pairs: groups.size, examples: examples}
          }
        end

        def skip_result
          {status: :ok, label: check_label, message: "#{@label} novel predicates: no database", details: {}}
        end
      end
    end
  end
end
