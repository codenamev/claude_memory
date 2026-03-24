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
      MAX_UNDISTILLED = 3
      MAX_TEXT_PER_ITEM = 1500

      QUERIES = {
        decisions: {query: "decision constraint rule requirement", scope: "all"},
        conventions: {query: "convention style format pattern prefer", scope: "all"},
        architecture: {query: "uses framework implements architecture pattern", scope: "all"}
      }.freeze

      def initialize(manager)
        @manager = manager
        @recall = Recall.new(manager)
      end

      def generate_context
        sections = []

        decisions = fetch(:decisions, MAX_DECISIONS)
        sections << format_section("Decisions", decisions) if decisions.any?

        conventions = fetch(:conventions, MAX_CONVENTIONS)
        sections << format_section("Conventions", conventions) if conventions.any?

        architecture = fetch(:architecture, MAX_ARCHITECTURE)
        sections << format_section("Architecture", architecture) if architecture.any?

        undistilled = fetch_undistilled(MAX_UNDISTILLED)
        sections << format_distillation_prompt(undistilled) if undistilled.any?

        return nil if sections.empty?

        sections.join("\n")
      end

      private

      def fetch(category, limit)
        config = QUERIES.fetch(category)
        results = @recall.query(config[:query], limit: limit, scope: config[:scope])
        results.map { |r| format_fact(r[:fact]) }
      rescue => e
        ClaudeMemory.logger.debug("ContextInjector#fetch(#{category}) failed: #{e.message}")
        []
      end

      def format_fact(fact)
        return nil unless fact

        subject = fact[:subject_name] || fact[:subject_entity_id]
        predicate = fact[:predicate]
        object = fact[:object_literal]

        if subject && predicate && object
          "#{subject}.#{predicate} = #{object}"
        elsif object
          object.to_s
        end
      end

      def fetch_undistilled(limit)
        stores = []
        if @manager.respond_to?(:project_store) && @manager.project_store
          stores << @manager.project_store
        end
        if @manager.respond_to?(:global_store) && @manager.global_store
          stores << @manager.global_store
        end

        items = stores.flat_map { |s|
          s.undistilled_content_items(limit: limit, min_length: 200)
        }

        items
          .sort_by { |i| i[:occurred_at] || "" }
          .reverse
          .first(limit)
      rescue => e
        ClaudeMemory.logger.debug("ContextInjector#fetch_undistilled failed: #{e.message}")
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
          "**What to skip:** debugging steps, code output, transient errors"
        ]

        items.each do |item|
          ago = Core::RelativeTime.format(item[:occurred_at]) || "unknown"
          raw = item[:raw_text] || ""
          truncated = (raw.length > MAX_TEXT_PER_ITEM) ? raw[0, MAX_TEXT_PER_ITEM] + "..." : raw
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
    end
  end
end
