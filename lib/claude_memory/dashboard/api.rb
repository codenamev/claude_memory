# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Dashboard
    # JSON API backend for the dashboard.
    # Reads from global and project SQLite databases.
    class API
      def initialize(manager)
        @manager = manager
      end

      def health
        checks = []

        checks << db_health("global", @manager.global_db_path)
        checks << db_health("project", @manager.project_db_path)
        checks << hooks_health
        checks << vec_health

        overall = if checks.any? { |c| c[:status] == "error" }
          "error"
        elsif checks.any? { |c| c[:status] == "warning" }
          "warning"
        else
          "healthy"
        end

        {status: overall, checks: checks, version: ClaudeMemory::VERSION}
      end

      def stats
        result = {databases: {}}

        {global: @manager.global_db_path, project: @manager.project_db_path}.each do |scope, path|
          result[:databases][scope] = if File.exist?(path)
            store = @manager.store_for_scope(scope.to_s)
            db_stats(store, path)
          else
            {exists: false}
          end
        end

        result
      end

      def activity(params = {})
        store = default_store
        return {events: [], summary: {}} unless store

        limit = (params["limit"] || 100).to_i
        event_type = params["event_type"]
        since = params["since"]

        events = ActivityLog.recent(store, limit: limit, event_type: event_type, since: since)
        summary = ActivityLog.summary(store, since: since)

        {
          event_count: events.size,
          summary: summary,
          events: events.map { |e|
            e[:occurred_ago] = Core::RelativeTime.format(e[:occurred_at])
            e
          }
        }
      end

      def facts(params = {})
        store = default_store
        return {facts: [], total: 0} unless store

        limit = (params["limit"] || 50).to_i
        offset = (params["offset"] || 0).to_i
        status_filter = params["status"] || "active"
        search = params["q"]

        dataset = store.facts.where(status: status_filter)
        dataset = dataset.where(Sequel.like(:predicate, "%#{search}%") | Sequel.like(:object_literal, "%#{search}%")) if search && !search.empty?

        total = dataset.count
        rows = dataset.order(Sequel.desc(:created_at)).limit(limit).offset(offset).all

        entity_ids = rows.flat_map { |r| [r[:subject_entity_id], r[:object_entity_id]] }.compact.uniq
        entities = store.entities.where(id: entity_ids).as_hash(:id)

        {
          total: total,
          limit: limit,
          offset: offset,
          facts: rows.map { |row|
            subject = entities[row[:subject_entity_id]]
            object_entity = entities[row[:object_entity_id]]
            {
              id: row[:id],
              docid: row[:docid],
              subject: subject&.dig(:canonical_name) || "unknown",
              predicate: row[:predicate],
              object: row[:object_literal] || object_entity&.dig(:canonical_name) || "unknown",
              status: row[:status],
              confidence: row[:confidence],
              scope: row[:scope],
              created_at: row[:created_at],
              created_ago: Core::RelativeTime.format(row[:created_at]),
              valid_from: row[:valid_from]
            }
          }
        }
      end

      def efficacy
        store = default_store
        return {recall_events: 0, total_results: 0, recent: []} unless store

        # Query recall events from activity log
        recall_events = ActivityLog.recent(store, limit: 200, event_type: "recall")

        total_results = recall_events.sum { |e| e.dig(:details, :result_count) || 0 }
        successful = recall_events.count { |e| e[:status] == "success" && (e.dig(:details, :result_count) || 0) > 0 }
        empty = recall_events.count { |e| e[:status] == "success" && (e.dig(:details, :result_count) || 0) == 0 }

        # Top queries by result count
        top_queries = recall_events
          .select { |e| e.dig(:details, :query) }
          .sort_by { |e| -(e.dig(:details, :result_count) || 0) }
          .first(10)
          .map { |e|
            {
              query: e.dig(:details, :query),
              tool: e.dig(:details, :tool),
              result_count: e.dig(:details, :result_count),
              duration_ms: e[:duration_ms],
              occurred_at: e[:occurred_at],
              occurred_ago: Core::RelativeTime.format(e[:occurred_at])
            }
          }

        {
          recall_events: recall_events.size,
          successful_recalls: successful,
          empty_recalls: empty,
          hit_rate: recall_events.empty? ? 0 : (successful.to_f / recall_events.size * 100).round(1),
          total_results_served: total_results,
          avg_results_per_query: recall_events.empty? ? 0 : (total_results.to_f / recall_events.size).round(1),
          top_queries: top_queries
        }
      end

      def timeline
        store = default_store
        return {days: []} unless store

        # Facts created per day (last 30 days)
        cutoff = (Time.now - 30 * 86400).utc.iso8601
        fact_rows = store.facts
          .where { created_at >= cutoff }
          .select_group(Sequel.lit("DATE(created_at)").as(:day))
          .select_append { count(id).as(:count) }
          .order(:day)
          .all

        content_rows = store.content_items
          .where { ingested_at >= cutoff }
          .select_group(Sequel.lit("DATE(ingested_at)").as(:day))
          .select_append { count(id).as(:count) }
          .order(:day)
          .all

        event_rows = if store.db.table_exists?(:activity_events)
          store.activity_events
            .where { occurred_at >= cutoff }
            .select_group(Sequel.lit("DATE(occurred_at)").as(:day), :event_type)
            .select_append { count(id).as(:count) }
            .order(:day)
            .all
        else
          []
        end

        # Merge into daily buckets
        all_days = (fact_rows.map { |r| r[:day] } +
                    content_rows.map { |r| r[:day] } +
                    event_rows.map { |r| r[:day] }).uniq.sort

        days = all_days.map { |day|
          fact_count = fact_rows.find { |r| r[:day] == day }&.dig(:count) || 0
          content_count = content_rows.find { |r| r[:day] == day }&.dig(:count) || 0
          day_events = event_rows.select { |r| r[:day] == day }

          {
            date: day,
            facts_created: fact_count,
            content_ingested: content_count,
            hook_events: day_events.sum { |r| r[:count] },
            recalls: day_events.select { |r| r[:event_type] == "recall" }.sum { |r| r[:count] }
          }
        }

        {days: days}
      end

      private

      def default_store
        if @manager.project_exists?
          @manager.ensure_project!
          @manager.project_store
        elsif @manager.global_exists?
          @manager.ensure_global!
          @manager.global_store
        end
      end

      def db_stats(store, path)
        {
          exists: true,
          path: path,
          size_bytes: File.size(path),
          facts_total: store.facts.count,
          facts_active: store.facts.where(status: "active").count,
          facts_superseded: store.facts.where(status: "superseded").count,
          entities_total: store.entities.count,
          content_items: store.content_items.count,
          open_conflicts: store.conflicts.where(status: "open").count,
          schema_version: store.schema_version,
          top_predicates: store.facts
            .where(status: "active")
            .group_and_count(:predicate)
            .order(Sequel.desc(:count))
            .limit(10)
            .all
            .map { |r| {predicate: r[:predicate], count: r[:count]} },
          entity_types: store.entities
            .group_and_count(:type)
            .order(Sequel.desc(:count))
            .all
            .map { |r| {type: r[:type], count: r[:count]} }
        }
      rescue => e
        {exists: true, path: path, error: e.message}
      end

      def db_health(label, path)
        unless File.exist?(path)
          return {
            name: "#{label}_database",
            status: "warning",
            message: "Not initialized",
            fix: "Run `claude-memory init` to create the #{label} database at #{path}."
          }
        end

        store = @manager.store_for_scope(label)
        version = store.schema_version
        {
          name: "#{label}_database",
          status: "healthy",
          message: "Schema v#{version}, #{store.facts.where(status: "active").count} active facts"
        }
      rescue => e
        {
          name: "#{label}_database",
          status: "error",
          message: e.message,
          fix: "Inspect the error above. Common causes: corrupt schema, file permissions, or a stale lock. Try `claude-memory recover --scope #{label}`, or remove the file at #{path} and re-run `claude-memory init`."
        }
      end

      HOOKS_SETTINGS_PATHS = [".claude/settings.json", ".claude/settings.local.json"].freeze

      def hooks_health
        present = collect_configured_hook_types
        expected = Commands::Checks::HooksCheck::EXPECTED_HOOKS
        missing = expected - present

        if present.empty?
          return {
            name: "hooks",
            status: "error",
            message: "No claude-memory hooks found in #{HOOKS_SETTINGS_PATHS.join(" or ")}",
            fix: "Run `claude-memory init` to install the standard hook set (#{expected.join(", ")})."
          }
        end

        if missing.empty?
          return {name: "hooks", status: "healthy", message: "All #{expected.size} hooks configured"}
        end

        {
          name: "hooks",
          status: "warning",
          message: "#{present.size}/#{expected.size} hooks configured",
          fix: "Missing hook(s): #{missing.join(", ")}. Run `claude-memory init` to install the standard set, or add them manually under `hooks.<EventName>[].hooks[]` in .claude/settings.json."
        }
      rescue => e
        {
          name: "hooks",
          status: "error",
          message: e.message,
          fix: "Failed to read hook settings. Verify .claude/settings.json is valid JSON, then re-run `claude-memory doctor`."
        }
      end

      # Walks the two-level hook structure Claude Code uses:
      # hooks.<EventName>[] -> matcher hash -> .hooks[] -> { type:, command: }
      def collect_configured_hook_types
        types = []
        HOOKS_SETTINGS_PATHS.each do |relpath|
          path = File.join(Dir.pwd, relpath)
          next unless File.exist?(path)

          settings = JSON.parse(File.read(path))
          hooks = settings["hooks"] || {}
          hooks.each do |event_type, matchers|
            next unless matchers.is_a?(Array)
            has_claude_memory = matchers.any? do |matcher|
              next false unless matcher.is_a?(Hash) && matcher["hooks"].is_a?(Array)
              matcher["hooks"].any? { |h| h.is_a?(Hash) && h["command"]&.include?("claude-memory") }
            end
            types << event_type if has_claude_memory
          end
        end
        types.uniq
      end

      def vec_health
        store = default_store
        unless store
          return {
            name: "vectors",
            status: "warning",
            message: "No database",
            fix: "Initialize a database first with `claude-memory init`."
          }
        end

        vec = store.vector_index
        if vec.available?
          coverage = vec.coverage_stats
          {name: "vectors", status: "healthy",
           message: "#{coverage[:vec_indexed]}/#{coverage[:facts_total]} facts indexed"}
        else
          {
            name: "vectors",
            status: "warning",
            message: "sqlite-vec not available",
            fix: "The sqlite-vec extension didn't load. Run `bundle install` to install the gem (>= 0.1.9). Semantic recall will be disabled until this is fixed; lexical recall still works."
          }
        end
      rescue => e
        {
          name: "vectors",
          status: "warning",
          message: e.message,
          fix: "Vector index threw an error. Try `claude-memory index --vec --rebuild` to rebuild from facts."
        }
      end
    end
  end
end
