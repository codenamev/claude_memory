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
        Conflicts.new(@manager).list(params)
      end

      def conflict_detail(id, scope = "project")
        Conflicts.new(@manager).detail(id, scope)
      end

      def reject_conflict_fact(id, side:, reason: nil, scope: "project")
        Conflicts.new(@manager).reject(id, side: side, reason: reason, scope: scope)
      end

      def reject_similar_conflicts(keeper_fact_id, reason: nil, scope: "project")
        Conflicts.new(@manager).reject_similar(keeper_fact_id, reason: reason, scope: scope)
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

      # Full detail view for a single fact — subject/predicate/object,
      # confidence, scope, status, full provenance chain (with session_id
      # and occurred_at from content_items). Supports either scope so
      # the frontend can drill into both project and global facts.
      def fact_detail(id, scope)
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = @manager.store_if_exists(scope)
        return {error: "#{scope} store not available"} unless store

        row = store.facts.where(id: id.to_i).first
        return {error: "Fact #{id} not found in #{scope}"} unless row

        detail = FactPresenter.new(store).with_provenance(row)
        detail.merge(source: scope, valid_from: row[:valid_from], valid_to: row[:valid_to])
      end

      # Reject a single fact (not a conflict side). Thin wrapper over
      # SQLiteStore#reject_fact which cascade-resolves any conflicts the
      # fact happened to be involved in.
      def reject_fact(id, reason: nil, scope: "project")
        return {error: "Invalid scope"} unless %w[global project].include?(scope)
        store = @manager.store_if_exists(scope)
        return {error: "#{scope} store not available"} unless store

        row = store.facts.where(id: id.to_i).first
        return {error: "Fact #{id} not found in #{scope}"} unless row

        result = store.reject_fact(id.to_i, reason: reason)
        {
          success: true,
          fact_id: id.to_i,
          scope: scope,
          conflicts_resolved: result[:conflicts_resolved] || 0
        }
      end

      # Live query tester. Reuses the production Recall pipeline so the
      # dashboard shows exactly what Claude would see via memory.recall.
      # Returns a bounded result set rendered through FactPresenter so
      # shapes line up with the other surfaces (Facts tab, conflict detail).
      def recall(params = {})
        query_text = params["query"].to_s.strip
        return {error: "query required"} if query_text.empty?

        scope = params["scope"] || "all"
        limit = (params["limit"] || 10).to_i.clamp(1, 50)
        intent = params["intent"]

        # Recall#query needs at least one store open. default_store gives
        # us the best available; the engine takes it from there.
        default_store
        recaller = ClaudeMemory::Recall.new(@manager)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = recaller.query(query_text, limit: limit, scope: scope, intent: intent)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        facts = results.is_a?(Array) ? results : (results[:facts] || [])
        {
          query: query_text,
          scope: scope,
          limit: limit,
          duration_ms: duration_ms,
          count: facts.size,
          facts: facts.map { |f| serialize_recall_fact(f) }
        }
      rescue => e
        msg = e.message
        # "disk image is malformed" from an FTS5 ORDER BY rank query almost
        # always means the FTS5 auxiliary index is out of sync (common
        # after a sqlite3 .recover restore or an interrupted write) — not
        # real DB corruption. Suggest the rebuild command inline so a user
        # looking at the dashboard knows exactly what to do.
        if msg.include?("disk image is malformed")
          {
            error: "Recall failed: #{msg}",
            hint: "Looks like the FTS5 index is out of sync. Try `claude-memory compact --scope project` (or --scope global) from a terminal to rebuild the search index. This is usually a harmless artifact of a prior DB recovery, not real corruption."
          }
        else
          {error: "Recall failed: #{msg}"}
        end
      end

      # Promote a project-scoped fact into the global store. Delegates to
      # StoreManager#promote_fact which copies the fact + entities +
      # provenance atomically inside a global-store transaction.
      def promote_fact(id)
        global_id = @manager.promote_fact(id.to_i)
        return {error: "Fact #{id} not found in project store"} if global_id.nil?

        {
          success: true,
          project_fact_id: id.to_i,
          global_fact_id: global_id
        }
      end

      def facts(params = {})
        scope = params["scope"] || "all"
        limit = (params["limit"] || 50).to_i
        offset = (params["offset"] || 0).to_i
        status_filter = params["status"] || "active"
        search = params["q"]

        stores = facts_stores_for(scope)
        return {facts: [], total: 0, limit: limit, offset: offset, scope: scope} if stores.empty?

        collected = stores.flat_map { |source, store|
          dataset = store.facts.where(status: status_filter)
          dataset = dataset.where(Sequel.like(:predicate, "%#{search}%") | Sequel.like(:object_literal, "%#{search}%")) if search && !search.empty?
          rows = dataset.order(Sequel.desc(:created_at)).all
          presented = FactPresenter.new(store).list_summary(rows)
          presented.map { |f| f.merge(source: source) }
        }
        collected.sort_by! { |f| -parse_timestamp(f[:created_at]) }

        {
          total: collected.size,
          limit: limit,
          offset: offset,
          scope: scope,
          facts: Array(collected[offset, limit])
        }
      end

      def efficacy(params = {})
        store = default_store
        since = params["since"]
        session_id = params["session_id"]
        session_id = nil if session_id.to_s.empty?
        return Efficacy::Reporter.report([], timeframe: {since: since, session_id: session_id}) unless store

        # Session-scope lookup: most MCP tool calls don't carry session_id
        # (Claude Code doesn't thread its session id into plugin MCP servers),
        # so we correlate by time window instead — we find the session's
        # first-to-most-recent activity from hook events (which do carry
        # session_id) and pick up recall events that fell inside that window.
        if session_id
          window = session_window(store, session_id)
          events = ActivityLog.recent(store, limit: 500, event_type: "recall", since: window[:since])
          events = events.select { |e|
            if e[:session_id].to_s.empty?
              # MCP tool calls typically arrive without a session_id; fall
              # back to time-window correlation with the session's hook
              # events (which do carry session_id).
              within_window?(e, window)
            else
              e[:session_id] == session_id
            end
          }
        else
          events = ActivityLog.recent(store, limit: 500, event_type: "recall", since: since)
        end

        Efficacy::Reporter.report(events, timeframe: {since: since, session_id: session_id})
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

      # Normalize a Recall result hash into the shape the dashboard's
      # recall tester table renders. Recall already returns shaped facts
      # (not raw DB rows), but the field names have drifted over versions
      # so we pull defensively.
      def serialize_recall_fact(f)
        {
          id: f[:id] || f["id"],
          docid: f[:docid] || f["docid"],
          subject: f[:subject] || f["subject"],
          predicate: f[:predicate] || f["predicate"],
          object: f[:object] || f["object"] || f[:object_literal] || f["object_literal"],
          scope: f[:scope] || f["scope"],
          source: f[:source] || f["source"],
          score: f[:score] || f["score"],
          confidence: f[:confidence] || f["confidence"],
          created_at: f[:created_at] || f["created_at"]
        }.compact
      end

      def parse_timestamp(value)
        Time.parse(value.to_s).to_i
      rescue ArgumentError, TypeError
        0
      end

      # Return the {since:, until:} ISO timestamps of the first-to-last
      # activity event we've seen for a given session_id. Used to correlate
      # MCP recall events (which typically lack session_id) back to the
      # Claude Code session that fired them via time proximity.
      def session_window(store, session_id)
        rows = store.activity_events.where(session_id: session_id).select(:occurred_at).all
        return {since: nil, until: nil} if rows.empty?
        timestamps = rows.map { |r| r[:occurred_at] }.compact
        {since: timestamps.min, until: timestamps.max}
      end

      def within_window?(event, window)
        return false unless window[:since] && window[:until]
        ts = event[:occurred_at]
        return false unless ts
        ts.between?(window[:since], window[:until])
      end

      def facts_stores_for(scope)
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

      def load_linked_facts(store, content_item_id)
        rows = store.db[:facts]
          .join(:provenance, fact_id: :id)
          .where(Sequel[:provenance][:content_item_id] => content_item_id.to_i)
          .select(Sequel[:facts].*)
          .all
        FactPresenter.new(store).list_summary(rows)
      end

      def load_facts_by_ids(store, ids)
        return [] if ids.nil? || ids.empty?
        rows = store.facts.where(id: ids.map(&:to_i)).all
        # Preserve the order given by the caller (ranking from recall).
        index = ids.each_with_index.to_h
        ordered = rows.sort_by { |r| index[r[:id]] || Float::INFINITY }
        FactPresenter.new(store).list_summary(ordered)
      end

      def default_store
        @manager.default_store(prefer: :project)
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
          indexed = coverage[:vec_indexed] || 0
          total = coverage[:with_embedding] || 0
          pct = coverage[:coverage_pct] || 0
          message = (total > 0) ? "#{indexed}/#{total} facts indexed (#{pct}%)" : "0 facts have embeddings yet"

          status = if total.zero? then "healthy"
          elsif pct < 10 then "error"
          elsif pct < 50 then "warning"
          else "healthy"
          end

          result = {name: "vectors", status: status, message: message}
          unless status == "healthy"
            result[:fix] = "Vector coverage is low — run `claude-memory index --vec --rebuild` to regenerate embeddings and reindex all active facts. Semantic recall accuracy degrades as this drops."
          end
          result
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
