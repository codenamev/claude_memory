# frozen_string_literal: true

module ClaudeMemory
  module Distill
    # Guards against the LLM distiller mislabeling reference material as
    # `convention`. Audited in production data on 2026-04-24: project facts
    # labeled `predicate=convention` with objects like "Cloud-backed Claude
    # Code plugin (~1,195 LOC JavaScript) using Supermemory API…" and
    # "Claude Code plugin with marketplace.json, 5,700+ stars, by Tobi Lütke."
    # These are descriptions of external projects, not conventions the user
    # applies. Leaving them under `convention` pollutes the Knowledge-base
    # sidebar and the `memory.conventions` MCP tool.
    #
    # Heuristic: only conventions are re-examined (decisions and architecture
    # notes about external projects are legitimately those predicates). A
    # convention is retagged to `reference` when its object text matches any
    # of the descriptive patterns below. Kept deliberately conservative —
    # false-positive retagging is worse than occasionally missing a case, so
    # the patterns target telltale numeric/attribution phrases that rarely
    # appear in real conventions.
    class ReferenceMaterialDetector
      # Recognizes descriptive prose about external software artifacts.
      PATTERNS = [
        # Line-of-code counts: "~1,195 LOC", "1200 lines of code"
        /~?\d+[,.]?\d*\s*(?:LOC|lines of code)/i,
        # Star counts: "5,700+ stars", "3.2k stars"
        /\d[\d,.]*\+?\s*(?:k\s+)?stars?\b/i,
        # Author attribution: "by Jane Doe", "by Tobi Lütke"
        /\bby\s+[[:upper:]][[:alpha:]'-]+\s+[[:upper:]][[:alpha:]'-]+/,
        # "X is a (plugin|library|tool|gem|service|framework|extension) …"
        /\b(?:is\s+an?|are)\s+(?:cloud-backed\s+)?(?:plugin|library|tool|gem|service|framework|extension|cli|mcp\s+server)\b/i,
        # Leading descriptor: "Plugin that…", "Library for…"
        /\A(?:cloud-backed\s+)?(?:plugin|library|tool|gem|service|framework|extension|cli|mcp\s+server)(?:\s+(?:with|using|for|that))/i
      ].freeze

      # Predicates we inspect. Decisions stay decisions even when they cite
      # external projects ("From QMD restudy: adopt X"); the guard targets
      # only `convention`, where misclassification is most common.
      GUARDED_PREDICATES = %w[convention].freeze

      def reclassify(extraction)
        return extraction if extraction.facts.nil? || extraction.facts.empty?

        new_facts = extraction.facts.map do |fact|
          if reference_material?(fact)
            fact.merge(predicate: "reference")
          else
            fact
          end
        end

        Distill::Extraction.new(
          entities: extraction.entities,
          facts: new_facts,
          decisions: extraction.decisions,
          signals: extraction.signals
        )
      end

      def reference_material?(fact)
        return false unless GUARDED_PREDICATES.include?(fact[:predicate].to_s)
        object = fact[:object].to_s
        return false if object.empty?
        PATTERNS.any? { |re| object.match?(re) }
      end
    end
  end
end
