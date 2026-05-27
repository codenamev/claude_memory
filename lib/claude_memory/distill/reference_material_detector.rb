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
      # Strong signals — any one of these on its own justifies reclassification.
      # Kept tight to avoid false positives on real conventions that happen
      # to quote external project names.
      STRONG_PATTERNS = [
        # Line-of-code counts: "~1,195 LOC", "1200 lines of code"
        /~?\d+[,.]?\d*\s*(?:LOC|lines of code)/i,
        # Star counts: "5,700+ stars", "3.2k stars"
        /\d[\d,.]*\+?\s*(?:k\s+)?stars?\b/i,
        # "X is a (plugin|library|tool|gem|service|framework|extension) …"
        /\b(?:is\s+an?|are)\s+(?:cloud-backed\s+)?(?:plugin|library|tool|gem|service|framework|extension|cli|mcp\s+server)\b/i,
        # Leading descriptor: "Plugin that…", "Library for…"
        /\A(?:cloud-backed\s+)?(?:plugin|library|tool|gem|service|framework|extension|cli|mcp\s+server)(?:\s+(?:with|using|for|that))/i
      ].freeze

      # Weak signals — only fire in combination with a strong signal.
      # Author attribution ("by Jane Doe") was originally a standalone
      # trigger, but production text like "MCP launched by Claude Code run
      # from PATH" contains the same surface pattern inside a legitimate
      # convention. Requiring a co-occurring strong signal keeps the guard
      # conservative.
      WEAK_PATTERNS = [
        /\bby\s+[[:upper:]][[:alpha:]'-]+\s+[[:upper:]][[:alpha:]'-]+/
      ].freeze

      # Predicates inspected for object-text reference signals. Decisions
      # stay decisions even when they cite external projects ("From QMD
      # restudy: adopt X"); the object-text guard targets only
      # `convention`, where misclassification is most common.
      GUARDED_PREDICATES = %w[convention].freeze

      # Stack-shaping single-value predicates that historically attract
      # hallucinations from CLAUDE.md-style example text ("e.g., this app
      # uses PostgreSQL"). For these predicates we additionally inspect the
      # source quote for example markers — if the LLM extracted a stack
      # fact from documentation example text, it's not a real project
      # commitment. Added 2026-05-21 after the audit found 10 open
      # conflicts driven by recurring example-text extraction.
      QUOTE_GUARDED_PREDICATES = %w[uses_database uses_framework uses_language deployment_platform auth_method].freeze

      # Example markers that signal the source text is documentation
      # exemplifying a scope/predicate concept, not a real stack claim.
      EXAMPLE_QUOTE_PATTERNS = [
        /\b(?:e\.?g\.?|i\.?e\.?|for example|for instance|such as)[,:]?\s/i,
        /\(\s*(?:e\.?g\.?|i\.?e\.?)[,.]/i
      ].freeze

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
        predicate = fact[:predicate].to_s
        return true if convention_with_reference_object?(fact, predicate)
        return true if stack_predicate_from_example_text?(fact, predicate)
        false
      end

      private

      def convention_with_reference_object?(fact, predicate)
        return false unless GUARDED_PREDICATES.include?(predicate)
        object = fact[:object].to_s
        return false if object.empty?
        STRONG_PATTERNS.any? { |re| object.match?(re) }
      end

      def stack_predicate_from_example_text?(fact, predicate)
        return false unless QUOTE_GUARDED_PREDICATES.include?(predicate)
        quote = fact[:quote].to_s
        return false if quote.empty?
        EXAMPLE_QUOTE_PATTERNS.any? { |re| quote.match?(re) }
      end
    end
  end
end
