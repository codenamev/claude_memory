# frozen_string_literal: true

module ClaudeMemory
  module Store
    # Episodic-observation CRUD for SQLiteStore.
    #
    # Extracted from SQLiteStore (module inclusion — the public API is
    # unchanged) so the store stays focused on core fact/entity/provenance
    # storage. Depends on the +observations+ table accessor, +with_retry+, and
    # +@db+ that remain on the including class. Append-only discipline
    # (tombstone via consolidated_into, never hard-delete) mirrors fact_links.
    module ObservationWrites
      # Insert an episodic observation. token_count is estimated from the body
      # when not supplied (rough ~4 chars/token) so Phase 2 budget math has a
      # value to work with.
      #
      # @param body [String] dense narrative text (required)
      # @param kind [String] one of Domain::Observation::KINDS
      # @param priority [Integer] 1=important, 2=maybe, 3=info
      # @param scope [String] "project" or "global"
      # @param project_path [String, nil] project directory for project-scoped rows
      # @param source_content_item_id [Integer, nil] provenance link to the raw chunk
      # @param session_id [String, nil] session that produced the observation
      # @param observed_at [String, nil] ISO 8601 event time (defaults to now UTC)
      # @param token_count [Integer, nil] precomputed token estimate
      # @return [Integer] inserted observation row id
      def insert_observation(body:, kind: "event", priority: 3, scope: "project",
        project_path: nil, source_content_item_id: nil, session_id: nil,
        observed_at: nil, token_count: nil)
        now = Time.now.utc.iso8601
        with_retry("insert_observation") do
          observations.insert(
            body: body,
            kind: kind,
            priority: priority,
            scope: scope,
            project_path: project_path,
            source_content_item_id: source_content_item_id,
            token_count: token_count || (body.length / 4.0).ceil,
            status: "active",
            session_id: session_id,
            observed_at: observed_at || now,
            created_at: now
          )
        end
      end

      # Fetch active observations, newest first. Used by the memory.observations
      # MCP tool and (later) the stable-prefix injection.
      #
      # @param scope [String, nil] filter by "project"/"global"; nil for any
      # @param limit [Integer] maximum rows to return
      # @param max_priority [Integer, nil] only rows with priority <= this value.
      #   Priority is inverted (1 = 🔴 important … 3 = 🟢 info), so a *higher*
      #   max_priority returns *more* rows: 1 returns only 🔴, nil returns all.
      # @return [Array<Hash>]
      def recent_observations(scope: nil, limit: 20, max_priority: nil)
        ds = observations.where(status: "active")
        ds = ds.where(scope: scope) if scope
        ds = ds.where { priority <= max_priority } if max_priority
        ds.order(Sequel.desc(:observed_at), Sequel.desc(:id)).limit(limit).all
      end

      # Tombstone an observation by pointing it at the consolidated row that
      # replaced it (append-only supersession — the row is preserved, not
      # deleted, mirroring fact_links). Used by the Reflector.
      #
      # @param observation_id [Integer] the superseded observation
      # @param into_id [Integer] the consolidated observation it was merged into
      # @return [Boolean] true if a row was updated
      def tombstone_observation(observation_id, into_id:)
        now = Time.now.utc.iso8601
        updated = observations.where(id: observation_id).update(
          status: "consolidated", consolidated_into: into_id, reflected_at: now
        )
        updated > 0
      end

      # Retire a stale observation (status "expired") without a consolidation
      # target. Append-only — the row is preserved for provenance, just
      # excluded from active recall. Used by the Reflector's TTL pass.
      #
      # @param observation_id [Integer]
      # @return [Boolean] true if a row was updated
      def expire_observation(observation_id)
        now = Time.now.utc.iso8601
        updated = observations.where(id: observation_id).update(status: "expired", reflected_at: now)
        updated > 0
      end

      # Fold a duplicate's sighting count into the keeper. Called by the
      # Reflector's dedup pass so corroboration survives consolidation — the
      # signal the promotion gate keys off.
      #
      # @param observation_id [Integer] keeper observation
      # @param by [Integer] how much to add (the loser's corroboration_count)
      # @return [Boolean] true if a row was updated (symmetric with the sibling
      #   mutators tombstone_observation/expire_observation/mark_observation_promoted)
      def increment_corroboration(observation_id, by: 1)
        updated = observations.where(id: observation_id)
          .update(corroboration_count: Sequel[:corroboration_count] + by)
        updated > 0
      end

      # Mark an observation as promoted to a structured fact. Append-only: the
      # row is preserved (provenance), it just stops being a promotion
      # candidate.
      #
      # @param observation_id [Integer]
      # @param fact_id [Integer] the fact this observation was promoted into
      # @return [Boolean] true if a row was updated
      def mark_observation_promoted(observation_id, fact_id:)
        now = Time.now.utc.iso8601
        updated = observations.where(id: observation_id)
          .update(promoted_at: now, promoted_fact_id: fact_id, reflected_at: now)
        updated > 0
      end

      # Semantic consolidation: merge several related observations into one
      # synthesized observation, atomically. The new row carries the *summed*
      # corroboration of its sources (combined sighting weight, which can tip it
      # over the promotion threshold); each source is tombstoned into it. This
      # is the Claude-as-reflector counterpart to the deterministic dedup — it
      # collapses observations that say the same thing in different words, which
      # exact-match dedup can't.
      #
      # @param from_ids [Array<Integer>] source observation ids (need >= 2 active in scope)
      # @param body [String] the synthesized observation text
      # @return [Hash, nil] {id:, merged:, corroboration_count:}, or nil when
      #   fewer than two of the ids are active in this scope
      def consolidate_observations(from_ids, body:, kind: "event", priority: 3, scope: "project",
        project_path: nil, source_content_item_id: nil, observed_at: nil)
        with_retry("consolidate_observations") do
          @db.transaction do
            # Read the source set *inside* the transaction so the rows we sum
            # corroboration from are the same rows we tombstone — otherwise two
            # reflectors (PreCompact + SessionEnd) could each read the same
            # active sources and double-count or re-tombstone them.
            sources = observations
              .where(id: from_ids, status: "active", scope: scope)
              .select(:id, :corroboration_count)
              .all
            next nil if sources.size < 2

            now = Time.now.utc.iso8601
            combined = sources.sum { |s| s[:corroboration_count] || 1 }

            new_id = observations.insert(
              body: body, kind: kind, priority: priority, scope: scope, project_path: project_path,
              source_content_item_id: source_content_item_id,
              token_count: (body.length / 4.0).ceil, corroboration_count: combined,
              status: "active", observed_at: observed_at || now, created_at: now
            )
            # Re-assert `active` on the update so a source consolidated by a
            # racing writer between read and write is not tombstoned twice.
            observations.where(id: sources.map { |s| s[:id] }, status: "active")
              .update(status: "consolidated", consolidated_into: new_id, reflected_at: now)
            {id: new_id, merged: sources.size, corroboration_count: combined}
          end
        end
      end

      # Active, not-yet-promoted observations corroborated at least
      # `min_corroboration` times — i.e. eligible for promotion to a fact.
      # Highest corroboration first.
      #
      # @param scope [String, nil] filter by scope; nil for any
      # @param min_corroboration [Integer] sightings required (the gate)
      # @param limit [Integer]
      # @return [Array<Hash>]
      def promotion_candidates(scope: nil, min_corroboration: 2, limit: 10)
        ds = observations.where(status: "active", promoted_at: nil)
        ds = ds.where(scope: scope) if scope
        ds.where { corroboration_count >= min_corroboration }
          .order(Sequel.desc(:corroboration_count), Sequel.desc(:observed_at))
          .limit(limit)
          .all
      end

      # Observations that were promoted into the given fact — the reverse of
      # promoted_fact_id, for fact→observation provenance.
      #
      # @param fact_id [Integer]
      # @return [Array<Hash>]
      def observations_for_fact(fact_id)
        observations
          .where(promoted_fact_id: fact_id)
          .select(:id, :body, :kind, :corroboration_count, :observed_at)
          .all
      end
    end
  end
end
