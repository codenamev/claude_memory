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
      MAX_TEXT_PER_ITEM = 1500
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
        sections << format_section("Decisions", decisions) if decisions.any?

        conventions = fetch(:conventions, MAX_CONVENTIONS)
        sections << format_section("Conventions", conventions) if conventions.any?

        architecture = fetch(:architecture, MAX_ARCHITECTURE)
        sections << format_section("Architecture", architecture) if architecture.any?

        # Block 1 of the two-block context: the episodic observation log. Sits
        # ahead of the (fresh-session) undistilled "Pending Knowledge Extraction"
        # tail (Block 2). Newest-first; only 🔴 carries a marker for the actor.
        observations = fetch_observations(MAX_OBSERVATIONS)
        @emitted_observation_count = observations.size
        obs_section = Observe::ObservationsRenderer.render(observations)
        sections << obs_section if obs_section

        if fresh_session?
          undistilled = fetch_undistilled(MAX_UNDISTILLED)
          sections << format_distillation_prompt(undistilled) if undistilled.any?

          promotion = fetch_promotion_candidates(MAX_PROMOTION_CANDIDATES)
          sections << format_observation_reflection(promotion) if promotion.any?

          mirror_candidates = fetch_mirror_candidates(MAX_MIRROR_CANDIDATES)
          if mirror_candidates.any?
            sections << format_auto_memory_mirror(mirror_candidates)
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

        format_observation_reflection(candidates)
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
          formatted = format_fact(fact)
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

      def format_fact(fact)
        return nil unless fact

        subject = fact[:subject_name] || fact[:subject_entity_id]
        predicate = fact[:predicate]
        object = fact[:object_literal]

        line = if subject && predicate && object
          "#{subject}.#{predicate} = #{object}"
        elsif object
          object.to_s
        end
        return nil unless line

        marker = Recall::StalenessAnnotator.marker_for(fact, threshold_days: stale_threshold_days)
        marker ? "#{line}  #{marker}" : line
      end

      def stale_threshold_days
        @stale_threshold_days ||= Configuration.new.injection_stale_days
      end

      # Automatic semantic reflection (Phase 4): surface observations that have
      # been corroborated past the promotion threshold so Claude can promote
      # them to facts inline, this session, at no extra API cost.
      def fetch_promotion_candidates(limit)
        stores = []
        stores << @manager.project_store if @manager.project_store
        stores << @manager.global_store if @manager.global_store

        stores
          .flat_map { |s| s.promotion_candidates(min_corroboration: Domain::Observation::PROMOTION_THRESHOLD, limit: limit) }
          .sort_by { |o| -(o[:corroboration_count] || 0) }
          .first(limit)
      rescue => e
        ClaudeMemory.logger.warn("ContextInjector#fetch_promotion_candidates failed: #{e.message}")
        []
      end

      def format_observation_reflection(candidates)
        lines = [
          "## Observation Reflection",
          "",
          "**Promote:** these observations have recurred enough to be worth committing",
          "as facts (corroboration gate passed). For each that represents a stable truth,",
          "call `memory.promote_observation(observation_id, predicate, object)` — embed a",
          "reason in the object (\"… because …\", \"… so that …\"). Skip noise / already-captured.",
          "",
          "**Consolidate:** if several observations in the log above (by `#id`) describe the",
          "same thing in different words, merge them with",
          "`memory.consolidate_observations(from_ids: […], body: \"<synthesis>\")`. Their",
          "corroboration combines, which can tip the merged observation past the promotion gate."
        ]

        candidates.each do |obs|
          lines << ""
          lines << "- [obs ##{obs[:id]} ×#{obs[:corroboration_count]}] #{obs[:body]}"
        end

        lines.join("\n")
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

      def format_distillation_prompt(items)
        lines = [
          "## Pending Knowledge Extraction",
          "",
          "The following transcript segments haven't been deeply analyzed yet.",
          "Extract facts, entities, and decisions, then call `memory.store_extraction`",
          "followed by `memory.mark_distilled` for each item.",
          "",
          "**What to extract:** technology decisions, conventions, preferences, architecture",
          "**What to skip:** debugging steps, code output, transient errors",
          "",
          "**Reasoning requirement:** decisions and conventions MUST embed a reason",
          "in the object (e.g., \"… because …\", \"… so that …\", \"caused by …\",",
          "\"breaks when …\"). A fact with a reason is recoverable once stale; a",
          "bare conclusion is dead weight. Prefer one fact-with-reason over two",
          "facts-without.",
          "",
          "**Also log what happened (episodic layer):** in the same",
          "`memory.store_extraction` call, populate `observations` — one per",
          "discrete event (a decision made, a preference stated, a notable action",
          "or outcome). Each: a concise `body` of what happened, a `kind`",
          "(decision/preference/event/…), and a reason for decisions/preferences.",
          "Observations record \"what happened\"; facts record \"what is true\". They",
          "accumulate, and a corroborated observation can later graduate into a fact."
        ]

        items.each do |item|
          ago = Core::RelativeTime.format(item[:occurred_at]) || "unknown"
          truncated = Core::TextBuilder.truncate(item[:raw_text], MAX_TEXT_PER_ITEM)
          lines << ""
          lines << "### Content Item #{item[:id]} (#{ago})"
          lines << truncated
        end

        lines.join("\n")
      end

      def format_section(title, items)
        items = items.compact.uniq
        return nil if items.empty?

        lines = ["## #{title}"]
        items.each { |item| lines << "- #{item}" }
        lines.join("\n")
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

      def format_auto_memory_mirror(candidates)
        lines = [
          "## Auto-Memory Mirror Candidates",
          "",
          "The following auto-memory entries (from `~/.claude/projects/<slug>/memory/`)",
          "are new or changed since the last mirror. Consider extracting them into",
          "claude_memory via `memory.store_extraction` so future sessions can recall",
          "them via `memory.conventions` / `memory.recall_semantic`.",
          "",
          "**Review discipline applies:** only extract high-signal entries (gotchas,",
          "feedback, references). Skip transient project state. Preserve the `**Why:**`",
          "and `**How to apply:**` reasoning when present."
        ]

        candidates.each do |candidate|
          lines << ""
          lines << "### #{candidate[:name]}"
          lines << candidate[:content]
        end

        lines.join("\n")
      end
    end
  end
end
