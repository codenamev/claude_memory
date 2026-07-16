# frozen_string_literal: true

module ClaudeMemory
  module Sweep
    # One-shot, on-demand data fixes for historical corpus damage — distinct
    # from Sweep::Maintenance's recurring, budgeted pruning. These run only when
    # a user explicitly invokes them (via `claude-memory dedupe-conflicts`,
    # `reclassify-references`, `restore`), never on the automatic sweep path, so
    # they carry dry-run support + rich decision logs rather than bare counts.
    #
    # Extracted from Maintenance (module/class split) so the recurring sweep
    # class stays focused on steady-state operations.
    class HistoricalCleanup
      # Short / noise tokens dropped before Jaccard comparison.
      # Intentionally minimal — we want conservative token extraction that
      # still treats "Rails 8.0" and "Rails 8.1" as overlapping.
      RESTORE_STOPWORDS = %w[for the and with via of in on to by is are].to_set.freeze
      RESTORE_JACCARD_THRESHOLD = 0.5

      attr_reader :store

      def initialize(store)
        @store = store
      end

      # Deduplicate open conflict rows that describe the same contradiction.
      # Fixes the pre-2026-04-24 tail where a repeated contradiction produced
      # one disputed fact + one conflict row per sighting. Groups by the
      # subject/predicate/object pair (order-insensitive, so A-vs-B == B-vs-A),
      # keeps the earliest conflict per group, resolves the rest.
      #
      # @param dry_run [Boolean] when true, decide but don't write
      # @return [Hash] {inspected:, resolved:, decisions: [{conflict_id:, action:, keeper_id:}]}
      def dedupe_open_conflicts(dry_run: false)
        result = {inspected: 0, resolved: 0, decisions: []}

        open_rows = @store.conflicts
          .where(status: "open")
          .order(:id)
          .all
        return result if open_rows.empty?

        fact_ids = open_rows.flat_map { |r| [r[:fact_a_id], r[:fact_b_id]] }.uniq
        facts = @store.facts
          .where(id: fact_ids)
          .select(:id, :subject_entity_id, :predicate, :object_literal, :status)
          .all
          .to_h { |f| [f[:id], f] }

        @store.db.transaction do
          groups = open_rows.group_by { |row| pair_key(row, facts) }.reject { |key, _| key.nil? }
          groups.each_value { |rows_in_group| resolve_conflict_group(rows_in_group, result, dry_run: dry_run) }
        end

        result
      end

      # Reclassify active facts currently labeled `convention` whose object
      # text matches the ReferenceMaterialDetector heuristics. Fixes the
      # historical data tail from before the detector was wired into
      # `store_extraction` on 2026-04-24. Current writes can't create this
      # pattern — this pass only cleans up what already exists.
      #
      # @param dry_run [Boolean] when true, decide but don't write
      # @return [Hash] {inspected:, reclassified:, decisions: [{fact_id:, object:}]}
      def reclassify_references(dry_run: false)
        detector = ClaudeMemory::Distill::ReferenceMaterialDetector.new
        result = {inspected: 0, reclassified: 0, decisions: []}

        candidates = @store.facts
          .where(status: "active", predicate: "convention")
          .select(:id, :object_literal)
          .all

        @store.db.transaction do
          candidates.each do |row|
            result[:inspected] += 1
            fact = {predicate: "convention", object: row[:object_literal]}
            next unless detector.reference_material?(fact)

            result[:decisions] << {fact_id: row[:id], object: row[:object_literal]}
            result[:reclassified] += 1

            unless dry_run
              @store.facts.where(id: row[:id]).update(predicate: "reference")
            end
          end
        end

        result
      end

      # Restore facts that were wrongly superseded back when a now-multi-value
      # predicate was still single-value. Only restores token-disjoint
      # supersessions (distinct claims that should coexist); token-overlapping
      # ones (likely genuine corrections) are left superseded. Rejected facts
      # (explicit user decisions) are never touched.
      #
      # Refuses to run on predicates still classified single-value — they
      # should stay superseded by design.
      #
      # @return [Hash] {inspected, restored, skipped_ambiguous, skipped_rejected, decisions}
      def restore_multi_value_supersessions(predicate:, dry_run: false)
        if ClaudeMemory::Resolve::PredicatePolicy.single?(predicate)
          raise ArgumentError, "Predicate '#{predicate}' is still classified single-value; refusing to restore"
        end

        result = {inspected: 0, restored: 0, skipped_ambiguous: 0, skipped_rejected: 0, decisions: []}

        rows_by_subject = @store.facts
          .where(predicate: predicate)
          .exclude(status: "rejected")
          .select(:id, :subject_entity_id, :object_literal, :status)
          .all
          .group_by { |r| r[:subject_entity_id] }

        rejected_by_subject = @store.facts
          .where(predicate: predicate, status: "rejected")
          .select(:id, :subject_entity_id, :object_literal)
          .all
          .group_by { |r| r[:subject_entity_id] }

        @store.db.transaction do
          rows_by_subject.each do |subject_id, rows|
            rejected_rows = rejected_by_subject[subject_id] || []
            siblings = rows + rejected_rows

            rows.each do |candidate|
              next unless candidate[:status] == "superseded"
              result[:inspected] += 1

              candidate_tokens = restore_tokenize(candidate[:object_literal])
              ambiguous_against = find_overlapping_siblings(candidate, siblings, candidate_tokens)

              if ambiguous_against.empty?
                result[:restored] += 1
                result[:decisions] << {
                  subject_entity_id: subject_id,
                  fact_id: candidate[:id],
                  object: candidate[:object_literal],
                  action: :restore
                }
                restore_fact!(candidate[:id]) unless dry_run
              else
                result[:skipped_ambiguous] += 1
                result[:decisions] << {
                  subject_entity_id: subject_id,
                  fact_id: candidate[:id],
                  object: candidate[:object_literal],
                  action: :skip_ambiguous,
                  overlaps_with: ambiguous_against.map { |s| s[:object_literal] }
                }
              end
            end
          end
        end

        result
      end

      private

      # Process one group of open conflicts sharing a subject/predicate/object
      # pair: keep the first, dedupe the rest into it. Mutates `result` with the
      # inspected/resolved counts + decision log. Counts are recorded whether or
      # not we write, so dry-run output matches a real run.
      def resolve_conflict_group(rows_in_group, result, dry_run:)
        result[:inspected] += rows_in_group.size
        return if rows_in_group.size < 2

        keeper = rows_in_group.first
        rows_in_group[1..].each do |dup|
          result[:decisions] << {
            conflict_id: dup[:id],
            action: :resolve_duplicate,
            keeper_id: keeper[:id],
            duplicate_fact_id: dup[:fact_b_id]
          }
          result[:resolved] += 1
          resolve_duplicate_conflict(keeper, dup) unless dry_run
        end
      end

      # Resolve a single duplicate conflict: reject its disputed side (fact_b_id
      # is always the newer inserted-as-disputed fact per Resolver convention),
      # shift that fact's provenance onto the keeper's fact_b so evidence isn't
      # lost, then mark the conflict resolved.
      def resolve_duplicate_conflict(keeper, dup)
        keeper_fact_b_id = keeper[:fact_b_id]
        if dup[:fact_b_id] != keeper_fact_b_id
          @store.provenance.where(fact_id: dup[:fact_b_id]).update(fact_id: keeper_fact_b_id)
          @store.facts.where(id: dup[:fact_b_id]).update(
            status: "rejected",
            valid_to: Time.now.utc.iso8601
          )
        end
        @store.conflicts.where(id: dup[:id]).update(
          status: "resolved",
          notes: "Deduplicated into conflict ##{keeper[:id]}"
        )
      end

      # Canonical key for grouping open conflicts. Two conflicts are the
      # "same" when they involve the same subject, predicate, and set of
      # objects (A-vs-B == B-vs-A). Missing-fact conflicts (either side
      # deleted) get a nil key and are skipped by the caller.
      def pair_key(conflict_row, facts_by_id)
        a = facts_by_id[conflict_row[:fact_a_id]]
        b = facts_by_id[conflict_row[:fact_b_id]]
        return nil unless a && b
        return nil unless a[:subject_entity_id] == b[:subject_entity_id]
        return nil unless a[:predicate] == b[:predicate]
        objects = [a[:object_literal].to_s.downcase.strip, b[:object_literal].to_s.downcase.strip].sort
        [a[:subject_entity_id], a[:predicate], objects]
      end

      def restore_tokenize(text)
        return Set.new if text.nil?
        text.downcase
          .scan(/[a-z0-9]+/)
          .reject { |t| t.length <= 2 || RESTORE_STOPWORDS.include?(t) }
          .to_set
      end

      def find_overlapping_siblings(candidate, siblings, candidate_tokens)
        siblings.select do |other|
          next false if other[:id] == candidate[:id]
          other_tokens = restore_tokenize(other[:object_literal])
          Core::Jaccard.score(candidate_tokens, other_tokens) >= RESTORE_JACCARD_THRESHOLD
        end
      end

      def restore_fact!(fact_id)
        @store.facts.where(id: fact_id).update(status: "active", valid_to: nil)
        @store.fact_links.where(to_fact_id: fact_id, link_type: "supersedes").delete
      end
    end
  end
end
