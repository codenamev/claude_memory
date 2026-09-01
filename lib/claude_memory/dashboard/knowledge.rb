# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    # Groups active facts into the categories a human cares about:
    # decisions, conventions/principles, quality guards, architecture, and
    # hard constraints. This is the bridge between internal predicate
    # vocabulary and the value categories the user expects to see —
    # "what decisions has Claude learned?" not "show me facts where
    # predicate='decision'".
    #
    # Quality guards are a heuristic split inside the conventions section:
    # convention-predicate facts whose object text starts with a prohibitive
    # or imperative ("Never", "Always", "Must", "Do not", "Don't"). These
    # are the rules that catch mistakes, not just describe preferences.
    class Knowledge
      QUALITY_GUARD_RE = /\A\s*(never|always|must|do not|don't)\b/i

      # Order matches how they appear in the UI — decisions first (highest
      # signal to a skeptical reader), references last (study notes about
      # external projects, kept distinct from conventions the user applies).
      SECTIONS = [
        {key: :decisions, label: "Decisions", description: "Explicit choices with a reason"},
        {key: :quality_guards, label: "Quality guards", description: "Rules that prevent mistakes"},
        {key: :conventions, label: "Conventions & principles", description: "Style, patterns, preferences"},
        {key: :architecture, label: "Architecture", description: "Structural knowledge"},
        {key: :constraints, label: "Constraints", description: "Hard tech-stack facts"},
        {key: :references, label: "References", description: "Study notes about external projects"}
      ].freeze

      TOP_PER_SECTION = 6

      def initialize(manager)
        @manager = manager
      end

      # @param params [Hash]
      #   "scope" — "project" (default), "global", or "all"
      #   "limit" — max facts returned per section (default 6)
      #   "section" — when set, returns *all* facts in that section (for the
      #     drawer "browse" view) instead of top N per section
      def summary(params = {})
        scope = params["scope"] || "all"
        limit = (params["limit"] || TOP_PER_SECTION).to_i
        section_filter = params["section"]&.to_sym

        rows = collect_rows(scope)
        sections = SECTIONS.map do |meta|
          all_in_section = rows.select { |r| classify_row(r[:fact]) == meta[:key] }
          shown = section_filter ? all_in_section : all_in_section.first(limit)
          {
            key: meta[:key],
            label: meta[:label],
            description: meta[:description],
            count: all_in_section.size,
            facts: shown.map { |r| r[:presented] }
          }
        end

        if section_filter
          sections = sections.select { |s| s[:key] == section_filter }
        end

        {
          scope: scope,
          section: section_filter,
          totals: {
            project: count_for_scope("project"),
            global: count_for_scope("global"),
            expiring: {
              project: count_for_scope("project", status: "expiring"),
              global: count_for_scope("global", status: "expiring")
            }
          },
          sections: sections
        }
      end

      private

      def count_for_scope(scope, status: "active")
        store = @manager.store_if_exists(scope)
        return 0 unless store
        store.facts.where(status: status).count
      rescue Sequel::DatabaseError
        0
      end

      def collect_rows(scope)
        stores = stores_for(scope)
        stores.flat_map do |source, store|
          rows = store.facts.where(status: "active").order(Sequel.desc(:confidence), Sequel.desc(:created_at)).all
          presenter = FactPresenter.new(store)
          presented = presenter.list_summary(rows)
          rows.zip(presented).map do |raw, p|
            {fact: raw, presented: p.merge(source: source)}
          end
        end
      end

      def stores_for(scope)
        case scope
        when "project"
          {"project" => @manager.store_if_exists("project")}.compact
        when "global"
          {"global" => @manager.store_if_exists("global")}.compact
        else
          {
            "project" => @manager.store_if_exists("project"),
            "global" => @manager.store_if_exists("global")
          }.compact
        end
      end

      # Maps a raw facts row to one of the SECTIONS keys. Uses PredicatePolicy
      # for the base section, then overlays the quality-guard heuristic on
      # convention facts.
      def classify_row(fact_row)
        predicate = fact_row[:predicate]
        object = fact_row[:object_literal].to_s

        base = Resolve::PredicatePolicy.section_for(predicate)
        case base
        when :decisions
          :decisions
        when :conventions
          object.match?(QUALITY_GUARD_RE) ? :quality_guards : :conventions
        when :constraints
          :constraints
        when :references
          :references
        else
          # :additional — architecture predicate lands here; split it out
          # explicitly since users reason about it differently.
          (predicate == "architecture") ? :architecture : :conventions
        end
      end
    end
  end
end
