# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Maps predicates to knowledge categories.
    # Provides a single source of truth for predicate-to-category mapping,
    # used by Resolver, NullDistiller, and Publish.
    #
    # Valid categories:
    #   decision     - architectural/technology decisions
    #   convention   - coding standards, style rules, naming patterns
    #   architecture - tech stack, frameworks, databases, platforms
    #   preference   - user preferences (often global scope)
    #   constraint   - hard requirements, limitations
    #   dependency   - what depends on what
    #   general      - uncategorized facts
    module CategoryInference
      VALID_CATEGORIES = %w[
        decision
        convention
        architecture
        preference
        constraint
        dependency
        general
      ].freeze

      # Exact predicate → category mappings
      PREDICATE_MAP = {
        "decision" => "decision",
        "convention" => "convention",
        "auth_method" => "architecture",
        "uses_database" => "architecture",
        "uses_framework" => "architecture",
        "deployment_platform" => "architecture",
        "testing_framework" => "architecture",
        "api_style" => "architecture",
        "architecture_pattern" => "architecture",
        "depends_on" => "dependency",
        "requires" => "dependency",
        "prefers" => "preference",
        "avoids" => "preference"
      }.freeze

      # Prefix/suffix patterns → category (checked in order)
      PATTERN_MAP = [
        [/\Adecided_/, "decision"],
        [/_convention\z/, "convention"],
        [/\Anaming_/, "convention"],
        [/\Auses_/, "architecture"],
        [/\Adeployment_/, "architecture"],
        [/_platform\z/, "architecture"],
        [/_framework\z/, "architecture"],
        [/\Adepends_/, "dependency"],
        [/\Arequires_/, "dependency"],
        [/\Aprefers_/, "preference"],
        [/\Aavoids_/, "preference"],
        [/\Aconstraint_/, "constraint"],
        [/_constraint\z/, "constraint"],
        [/_rule\z/, "constraint"]
      ].freeze

      def self.infer(predicate, explicit_category: nil)
        # Explicit category takes precedence if valid
        return explicit_category if explicit_category && VALID_CATEGORIES.include?(explicit_category)

        # Exact match
        return PREDICATE_MAP[predicate] if PREDICATE_MAP.key?(predicate)

        # Pattern match
        PATTERN_MAP.each do |pattern, category|
          return category if predicate&.match?(pattern)
        end

        "general"
      end

      def self.valid?(category)
        VALID_CATEGORIES.include?(category)
      end
    end
  end
end
