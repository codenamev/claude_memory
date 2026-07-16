# frozen_string_literal: true

module ClaudeMemory
  module Hook
    # Generates context for SessionStart hook injection.
    # Queries both global and project databases for key facts
    # and formats them as concise context for Claude.
    class ContextInjector
      MAX_DECISIONS = 5
      MAX_CONVENTIONS = 5
      MAX_ARCHITECTURE = 5
      MAX_OBSERVATIONS = 10
      MAX_PROMOTION_CANDIDATES = 5
      MAX_UNDISTILLED = 3
      MAX_MIRROR_CANDIDATES = 5

      FRESH_SESSION_SOURCES = %w[startup resume clear].freeze

      QUERIES = {
        decisions: {query: "decision constraint rule requirement", scope: "all"},
        conventions: {query: "convention style format pattern prefer", scope: "all"},
        architecture: {query: "uses framework implements architecture pattern", scope: "all"}
      }.freeze

      # Fact IDs and subjects that `generate_context` injected on the most recent
      # call. Both are empty until `generate_context` has been invoked. Populated
      # in call order (decisions → conventions → architecture) so benchmark
      # harnesses can attribute sections if they care.
      #
      # emitted_facts_by_scope groups the IDs by the DB they came from
      # ({"project" => [...], "global" => [...]}) so telemetry can resolve
      # each fact from the correct store. Fact IDs autoincrement per-DB,
      # so a bare ID without scope is ambiguous.
      attr_reader :emitted_fact_ids, :emitted_subjects, :emitted_facts_by_scope,
        :emitted_observation_count

      def initialize(manager, source: nil, auto_memory_mirror: nil, stale_threshold_days: nil)
        @manager = manager
        @source = source
        @recall = Recall.new(manager)
        @auto_memory_mirror = auto_memory_mirror
        @stale_threshold_days = stale_threshold_days
        @emitted_fact_ids = []
        @emitted_subjects = []
        @emitted_facts_by_scope = Hash.new { |h, k| h[k] = [] }
        @emitted_observation_count = 0
      end

      def generate_context
        @emitted_fact_ids = []
        @emitted_subjects = []
        @emitted_facts_by_scope = Hash.new { |h, k| h[k] = [] }
        @emitted_observation_count = 0
        sections = []

        decisions = fetch(:decisions, MAX_DECISIONS)
        sections << ContextPresenter.section("Decisions", decisions) if decisions.any?

        conventions = fetch(:conventions, MAX_CONVENTIONS)
        sections << ContextPresenter.section("Conventions", conventions) if conventions.any?

        architecture = fetch(:architecture, MAX_ARCHITECTURE)
        sections << ContextPresenter.section("Architecture", architecture) if architecture.any?

        # Block 1 of the two-block context: the episodic observation log. Sits
        # ahead of the (fresh-session) undistilled "Pending Knowledge Extraction"
        # tail (Block 2). Newest-first; only 🔴 carries a marker for the actor.
        observations = fetch_observations(MAX_OBSERVATIONS)
        @emitted_observation_count = observations.size
        obs_section = Observe::ObservationsRenderer.render(observations)
        sections << obs_section if obs_section

        if fresh_session?
          undistilled = fetch_undistilled(MAX_UNDISTILLED)
          if undistilled.any?
            sections << ContextPresenter.distillation_prompt(undistilled)
            # The episodic-capture ask is its own prominent section (#72), not a
            # buried paragraph inside the deep-distill prompt.
            sections << ContextPresenter.observation_capture_prompt
          end

          promotion = fetch_promotion_candidates(MAX_PROMOTION_CANDIDATES)
          sections << ContextPresenter.observation_reflection(promotion) if promotion.any?

          mirror_candidates = fetch_mirror_candidates(MAX_MIRROR_CANDIDATES)
          if mirror_candidates.any?
            sections << ContextPresenter.auto_memory_mirror(mirror_candidates)
            auto_memory_mirror.commit(mirror_candidates)
          end
        end

        return nil if sections.empty?

        sections.join("\n")
      end

      # Reflection-only context for PreCompact (context pressure) — just the
      # promote/consolidate instructions for corroborated/related observations.
      # PreCompact is the analog of Mastra's token-threshold reflection trigger;
      # at compaction we nudge the Claude-as-reflector pass rather than
      # re-inject the full snapshot (which would add tokens as the window fills).
      # @return [String, nil]
      def reflection_context
        candidates = fetch_promotion_candidates(MAX_PROMOTION_CANDIDATES)
        return nil if candidates.empty?

        ContextPresenter.observation_reflection(candidates)
      end

      private

      def fresh_session?
        @source.nil? || FRESH_SESSION_SOURCES.include?(@source)
      end

      def fetch(category, limit)
        config = QUERIES.fetch(category)
        results = @recall.query(config[:query], limit: limit, scope: config[:scope])
        results.filter_map do |r|
          fact = r[:fact]
          next unless fact
          formatted = ContextPresenter.fact_line(fact, stale_threshold_days: stale_threshold_days)
          next unless formatted
          if fact[:id]
            @emitted_fact_ids << fact[:id]
            scope_key = (r[:source] || fact[:scope] || "project").to_s
            @emitted_facts_by_scope[scope_key] << fact[:id]
          end
          subject = fact[:subject_name] || fact[:subject_entity_id]
          @emitted_subjects << subject.to_s if subject
          formatted
        end
      rescue => e
        ClaudeMemory.logger.debug("ContextInjector#fetch(#{category}) failed: #{e.message}")
        []
      end

      def stale_threshold_days
        @stale_threshold_days ||= Configuration.new.injection_stale_days
      end

      # Automatic semantic reflection (Phase 4): surface observations that have
      # been corroborated past the promotion threshold so Claude can promote
      # them to facts inline, this session, at no extra API cost.
      # Project store only: the reflection nudge renders bare `[obs #<id>]` and
      # `memory.promote_observation`/`consolidate_observations` default to the
      # project scope. Observation ids autoincrement *per-DB*, so mixing in
      # global-store candidates would route a promote call to the wrong DB.
      # Observations are written project-scoped on the ingest path today; if a
      # global observation writer is ever added, scope-tag the nudge line
      # (mirror @emitted_facts_by_scope) before broadening this.
      def fetch_promotion_candidates(limit)
        store = @manager.project_store
        return [] unless store

        store
          .promotion_candidates(min_corroboration: Domain::Observation::PROMOTION_THRESHOLD, limit: limit)
          .sort_by { |o| -(o[:corroboration_count] || 0) }
          .first(limit)
      rescue => e
        ClaudeMemory.logger.warn("ContextInjector#fetch_promotion_candidates failed: #{e.message}")
        []
      end

      def fetch_observations(limit)
        stores = []
        stores << @manager.project_store if @manager.project_store
        stores << @manager.global_store if @manager.global_store

        stores
          .flat_map { |s| s.recent_observations(limit: limit) }
          .sort_by { |o| o[:observed_at] || "" }
          .reverse
          .first(limit)
      rescue => e
        ClaudeMemory.logger.warn("ContextInjector#fetch_observations failed: #{e.message}")
        []
      end

      def fetch_undistilled(limit)
        stores = []
        stores << @manager.project_store if @manager.project_store
        stores << @manager.global_store if @manager.global_store

        items = stores.flat_map { |s|
          s.undistilled_content_items(limit: limit, min_length: 200)
        }

        items
          .sort_by { |i| i[:occurred_at] || "" }
          .reverse
          .first(limit)
      rescue => e
        ClaudeMemory.logger.warn("ContextInjector#fetch_undistilled failed: #{e.message}")
        []
      end

      def fetch_mirror_candidates(limit)
        mirror = auto_memory_mirror
        return [] unless mirror
        mirror.pending_candidates(limit: limit)
      rescue => e
        ClaudeMemory.logger.warn("ContextInjector#fetch_mirror_candidates failed: #{e.message}")
        []
      end

      def auto_memory_mirror
        @auto_memory_mirror ||= build_default_mirror
      end

      def build_default_mirror
        project_path = @manager.respond_to?(:project_path) ? @manager.project_path : nil
        return nil unless project_path

        config = Configuration.new
        AutoMemoryMirror.new(
          auto_memory_dir: AutoMemoryMirror.default_dir(project_path, config.claude_config_dir),
          state_file: AutoMemoryMirror.default_state_file(project_path)
        )
      rescue => e
        ClaudeMemory.logger.debug("ContextInjector#build_default_mirror failed: #{e.message}")
        nil
      end
    end
  end
end
