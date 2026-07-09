# frozen_string_literal: true

module ClaudeMemory
  module Hook
    # Pure presentation for SessionStart context injection. Turns
    # already-fetched rows (facts, observations, undistilled items, mirror
    # candidates) into the markdown section strings that ContextInjector
    # assembles and joins.
    #
    # No I/O, no StoreManager, no Configuration — every method is a data → string
    # transform, so the exact injected text can be unit-tested directly.
    # ContextInjector remains the imperative shell that fetches and delegates.
    module ContextPresenter
      MAX_TEXT_PER_ITEM = 1500

      module_function

      # A titled bullet list, or nil when there's nothing to show.
      def section(title, items)
        items = items.compact.uniq
        return nil if items.empty?

        lines = ["## #{title}"]
        items.each { |item| lines << "- #{item}" }
        lines.join("\n")
      end

      # One fact rendered as "subject.predicate = object" (or bare object),
      # with a staleness marker appended when applicable. Returns nil when the
      # fact can't produce a line.
      def fact_line(fact, stale_threshold_days:)
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

      def observation_reflection(candidates)
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

      def distillation_prompt(items)
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
          "facts-without."
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

      # First-class, standalone ask for the episodic layer (#72). Authoring
      # observations was previously a paragraph buried inside the optional
      # deep-distill flow, and that flow fires almost never — so the episodic
      # log was 100% Layer-1 scrapes. This decouples it: a prominent,
      # lightweight instruction to log "what happened" directly, the same way
      # the fact context rides the session. Effectiveness is measurable via the
      # `mcp_extraction` content-item source (Layer-2) vs `claude_code` (Layer-1).
      def observation_capture_prompt
        <<~PROMPT.strip
          ## Log What Happened (episodic memory)

          Record the recent narrative as **observations** — "what happened",
          complementing the facts above ("what is true"). For each discrete
          event in the recent work above (a decision made, a preference stated,
          a notable fix or outcome), call `memory.store_extraction` with an
          `observations` array — one entry per event:

          - `body`: one concise sentence of what happened (embed a reason for
            decisions/preferences — "… because …", "… so that …")
          - `kind`: `decision`, `preference`, or `event`
          - `priority`: 1 important, 2 maybe, 3 info

          Keep it to genuine events worth remembering — skip routine steps and
          code output. Observations accumulate and a corroborated one graduates
          into a fact. Send them with the facts in the same call, or on their own.
        PROMPT
      end

      def auto_memory_mirror(candidates)
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
