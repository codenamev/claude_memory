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

      def conflicts(params = {})
        scope = params["scope"] || "all"
        status_filter = params["status"] || "open"
        limit = (params["limit"] || 50).to_i
        offset = (params["offset"] || 0).to_i

        stores = conflict_stores(scope)
        rows = stores.flat_map { |source, store|
          dataset = store.conflicts
          dataset = dataset.where(status: status_filter) unless status_filter == "all"
          dataset.all.map { |row| row.merge(source: source, store: store) }
        }

        rows = rows.sort_by { |r| -parse_timestamp(r[:detected_at]) }
        total = rows.size
        page = rows[offset, limit] || []

        {
          total: total,
          limit: limit,
          offset: offset,
          scope: scope,
          status: status_filter,
          conflicts: page.map { |row| serialize_conflict_row(row) }
        }
      end

      def conflict_detail(id, scope = "project")
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = scope_store(scope)
        return {error: "#{scope} store not available"} unless store

        row = store.conflicts.where(id: id.to_i).first
        return {error: "Conflict #{id} not found"} unless row

        {
          conflict: {
            id: row[:id],
            status: row[:status],
            detected_at: row[:detected_at],
            detected_ago: Core::RelativeTime.format(row[:detected_at]),
            notes: row[:notes],
            source: scope
          },
          fact_a: load_conflict_fact(store, row[:fact_a_id]),
          fact_b: load_conflict_fact(store, row[:fact_b_id])
        }
      end

      def reject_conflict_fact(id, side:, reason: nil, scope: "project")
        return {error: "Invalid side (must be 'a' or 'b')"} unless %w[a b].include?(side)
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = scope_store(scope)
        return {error: "#{scope} store not available"} unless store

        row = store.conflicts.where(id: id.to_i).first
        return {error: "Conflict #{id} not found"} unless row

        fact_id = (side == "a") ? row[:fact_a_id] : row[:fact_b_id]
        result = store.reject_fact(fact_id, reason: reason)

        {
          success: true,
          conflict_id: id,
          rejected_fact_id: fact_id,
          side: side,
          scope: scope,
          conflicts_resolved: result[:conflicts_resolved]
        }
      end

      def session_summary(session_id)
        store = default_store
        return {session_id: session_id, events: 0} unless store && session_id

        events = store.activity_events.where(session_id: session_id).all
        recalls = events.select { |e| e[:event_type] == "recall" }
        stores = events.select { |e| e[:event_type] == "store_extraction" }
        ingests = events.select { |e| e[:event_type] == "hook_ingest" }

        facts_recalled = recalls.sum { |e|
          details = e[:detail_json] ? JSON.parse(e[:detail_json], symbolize_names: true) : {}
          details[:result_count] || 0
        }
        facts_stored = stores.sum { |e|
          details = e[:detail_json] ? JSON.parse(e[:detail_json], symbolize_names: true) : {}
          details[:facts_created] || 0
        }
        total_latency = events.sum { |e| e[:duration_ms] || 0 }

        {
          session_id: session_id,
          events: events.size,
          recalls: recalls.size,
          facts_recalled: facts_recalled,
          facts_stored: facts_stored,
          ingests: ingests.size,
          total_latency_ms: total_latency
        }
      end

      def activity_detail(id)
        store = default_store
        return {error: "No database available"} unless store

        row = store.activity_events.where(id: id.to_i).first
        return {error: "Event #{id} not found"} unless row

        details = row[:detail_json] ? JSON.parse(row[:detail_json], symbolize_names: true) : {}
        event = row.merge(
          details: details,
          occurred_ago: Core::RelativeTime.format(row[:occurred_at])
        )
        event.delete(:detail_json)

        content_item_id = details[:content_id] || details[:content_item_id]
        content_item = content_item_id ? load_content_item(store, content_item_id) : nil
        linked_facts = if content_item_id
          load_linked_facts(store, content_item_id)
        elsif details[:top_fact_ids].is_a?(Array) && !details[:top_fact_ids].empty?
          load_facts_by_ids(store, details[:top_fact_ids])
        else
          []
        end

        {
          event: event,
          content_item: content_item,
          linked_facts: linked_facts
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

      def efficacy(params = {})
        store = default_store
        return empty_efficacy unless store

        since = params["since"]
        session_id = params["session_id"]

        recall_events = ActivityLog.recent(store, limit: 500, event_type: "recall", since: since)
        recall_events = recall_events.select { |e| e[:session_id] == session_id } if session_id

        result_counts = recall_events.map { |e| e.dig(:details, :result_count) || 0 }
        latencies = recall_events.map { |e| e[:duration_ms] }.compact
        successful = recall_events.count { |e| e[:status] == "success" && (e.dig(:details, :result_count) || 0) > 0 }
        empty = recall_events.count { |e| e[:status] == "success" && (e.dig(:details, :result_count) || 0) == 0 }

        {
          timeframe: {since: since, session_id: session_id},
          recall_events: recall_events.size,
          successful_recalls: successful,
          empty_recalls: empty,
          hit_rate: percentage(successful, recall_events.size),
          total_results_served: result_counts.sum,
          median_results_per_query: median(result_counts),
          median_latency_ms: median(latencies),
          tool_mix: tool_mix(recall_events),
          memory_gaps: memory_gaps(recall_events),
          recall_trace: recall_trace(recall_events)
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

      CONTENT_ITEM_PREVIEW_BYTES = 8000
      RECALL_TRACE_LIMIT = 50
      MEMORY_GAPS_LIMIT = 10

      def empty_efficacy
        {
          timeframe: {since: nil, session_id: nil},
          recall_events: 0,
          successful_recalls: 0,
          empty_recalls: 0,
          hit_rate: 0,
          total_results_served: 0,
          median_results_per_query: 0,
          median_latency_ms: 0,
          tool_mix: [],
          memory_gaps: [],
          recall_trace: []
        }
      end

      def percentage(part, whole)
        return 0 if whole.to_i.zero?
        (part.to_f / whole * 100).round(1)
      end

      def median(values)
        return 0 if values.empty?
        sorted = values.sort
        mid = sorted.size / 2
        if sorted.size.odd?
          sorted[mid]
        else
          ((sorted[mid - 1] + sorted[mid]) / 2.0).round(1)
        end
      end

      def tool_mix(events)
        events
          .group_by { |e| e.dig(:details, :tool) || "(unknown)" }
          .map { |tool, rows|
            hits = rows.count { |r| (r.dig(:details, :result_count) || 0) > 0 }
            {
              tool: tool,
              count: rows.size,
              hits: hits,
              hit_rate: percentage(hits, rows.size)
            }
          }
          .sort_by { |row| -row[:count] }
      end

      def memory_gaps(events)
        events
          .select { |e| (e.dig(:details, :result_count) || 0).zero? && e.dig(:details, :query) }
          .first(MEMORY_GAPS_LIMIT)
          .map { |e|
            {
              tool: e.dig(:details, :tool),
              query: e.dig(:details, :query),
              occurred_at: e[:occurred_at],
              occurred_ago: Core::RelativeTime.format(e[:occurred_at])
            }
          }
      end

      def recall_trace(events)
        events.first(RECALL_TRACE_LIMIT).map { |e|
          {
            id: e[:id],
            tool: e.dig(:details, :tool),
            query: e.dig(:details, :query),
            result_count: e.dig(:details, :result_count) || 0,
            duration_ms: e[:duration_ms],
            session_id: e[:session_id],
            status: e[:status],
            occurred_at: e[:occurred_at],
            occurred_ago: Core::RelativeTime.format(e[:occurred_at])
          }
        }
      end

      def load_content_item(store, id)
        row = store.content_items.where(id: id.to_i).first
        return nil unless row

        raw = row[:raw_text].to_s
        truncated = raw.bytesize > CONTENT_ITEM_PREVIEW_BYTES
        preview = truncated ? raw.byteslice(0, CONTENT_ITEM_PREVIEW_BYTES) : raw

        {
          id: row[:id],
          source: row[:source],
          session_id: row[:session_id],
          transcript_path: row[:transcript_path],
          project_path: row[:project_path],
          byte_len: row[:byte_len],
          occurred_at: row[:occurred_at],
          ingested_at: row[:ingested_at],
          raw_text_preview: preview,
          truncated: truncated
        }
      end

      FACT_PREVIEW_CHARS = 120

      def parse_timestamp(value)
        Time.parse(value.to_s).to_i
      rescue ArgumentError, TypeError
        0
      end

      def conflict_stores(scope)
        result = {}
        if (scope == "all" || scope == "global") && @manager.global_exists?
          @manager.ensure_global!
          result["global"] = @manager.global_store
        end
        if (scope == "all" || scope == "project") && @manager.project_exists?
          @manager.ensure_project!
          result["project"] = @manager.project_store
        end
        result
      end

      def scope_store(scope)
        case scope
        when "project"
          return nil unless @manager.project_exists?
          @manager.ensure_project!
          @manager.project_store
        when "global"
          return nil unless @manager.global_exists?
          @manager.ensure_global!
          @manager.global_store
        end
      end

      def serialize_conflict_row(row)
        store = row[:store]
        {
          id: row[:id],
          fact_a_id: row[:fact_a_id],
          fact_b_id: row[:fact_b_id],
          fact_a_preview: fact_preview(store, row[:fact_a_id]),
          fact_b_preview: fact_preview(store, row[:fact_b_id]),
          status: row[:status],
          detected_at: row[:detected_at],
          detected_ago: Core::RelativeTime.format(row[:detected_at]),
          notes: row[:notes],
          source: row[:source]
        }
      end

      def fact_preview(store, fact_id)
        row = store.facts.where(id: fact_id).first
        return nil unless row

        subject_entity = row[:subject_entity_id] ? store.entities.where(id: row[:subject_entity_id]).first : nil
        object_entity = row[:object_entity_id] ? store.entities.where(id: row[:object_entity_id]).first : nil
        object_text = row[:object_literal] || object_entity&.dig(:canonical_name) || "unknown"
        truncated = object_text.to_s.size > FACT_PREVIEW_CHARS

        {
          id: row[:id],
          docid: row[:docid],
          subject: subject_entity&.dig(:canonical_name) || "unknown",
          predicate: row[:predicate],
          object: truncated ? "#{object_text[0, FACT_PREVIEW_CHARS]}…" : object_text,
          status: row[:status]
        }
      end

      def load_conflict_fact(store, fact_id)
        row = store.facts.where(id: fact_id).first
        return nil unless row

        subject_entity = row[:subject_entity_id] ? store.entities.where(id: row[:subject_entity_id]).first : nil
        object_entity = row[:object_entity_id] ? store.entities.where(id: row[:object_entity_id]).first : nil

        provenance_rows = store.provenance.where(fact_id: fact_id).all
        content_item_ids = provenance_rows.map { |p| p[:content_item_id] }.compact.uniq
        content_items = content_item_ids.empty? ? {} : store.content_items.where(id: content_item_ids).as_hash(:id)

        {
          id: row[:id],
          docid: row[:docid],
          subject: subject_entity&.dig(:canonical_name) || "unknown",
          predicate: row[:predicate],
          object: row[:object_literal] || object_entity&.dig(:canonical_name) || "unknown",
          status: row[:status],
          confidence: row[:confidence],
          scope: row[:scope],
          created_at: row[:created_at],
          created_ago: Core::RelativeTime.format(row[:created_at]),
          provenance: provenance_rows.map { |prov|
            ci = prov[:content_item_id] ? content_items[prov[:content_item_id]] : nil
            {
              quote: prov[:quote],
              strength: prov[:strength],
              content_item_id: prov[:content_item_id],
              session_id: ci&.dig(:session_id),
              occurred_at: ci&.dig(:occurred_at)
            }
          }
        }
      end

      def load_linked_facts(store, content_item_id)
        rows = store.db[:facts]
          .join(:provenance, fact_id: :id)
          .where(Sequel[:provenance][:content_item_id] => content_item_id.to_i)
          .select(Sequel[:facts].*)
          .all
        serialize_facts(store, rows)
      end

      def load_facts_by_ids(store, ids)
        return [] if ids.nil? || ids.empty?
        rows = store.facts.where(id: ids.map(&:to_i)).all
        # Preserve the order given by the caller (ranking from recall)
        index = ids.each_with_index.to_h
        ordered = rows.sort_by { |r| index[r[:id]] || Float::INFINITY }
        serialize_facts(store, ordered)
      end

      def serialize_facts(store, rows)
        entity_ids = rows.flat_map { |r| [r[:subject_entity_id], r[:object_entity_id]] }.compact.uniq
        entities = entity_ids.empty? ? {} : store.entities.where(id: entity_ids).as_hash(:id)

        rows.map { |row|
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
            created_at: row[:created_at]
          }
        }
      end

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
