# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Dashboard
    # JSON API backend for the dashboard. Routes/delegates to dedicated
    # collaborator classes (Conflicts, Moments, Trust, Knowledge, Reuse,
    # Timeline, Health, FactPresenter) for non-trivial logic; this class
    # holds HTTP-shape concerns and the long-tail per-endpoint formatting
    # that hasn't yet been extracted.
    class API
      def initialize(manager)
        @manager = manager
      end

      def health
        Health.new(@manager).report
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

      def moments(params = {})
        Moments.new(@manager).list(params)
      end

      def trust
        Trust.new(@manager).snapshot
      end

      def knowledge(params = {})
        Knowledge.new(@manager).summary(params)
      end

      def reuse(params = {})
        Reuse.new(@manager).top(params)
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

      def moment_feedback(event_id, verdict:, note: nil)
        store = default_store
        return {error: "No project store"} unless store
        return {error: "Invalid verdict (must be 'up' or 'down')"} unless %w[up down].include?(verdict)
        event = store.activity_events.where(id: event_id.to_i).first
        return {error: "Moment #{event_id} not found"} unless event

        row = store.upsert_moment_feedback(event_id: event_id.to_i, verdict: verdict, note: note)
        {success: true, feedback: serialize_feedback(row)}
      end

      def clear_moment_feedback(event_id)
        store = default_store
        return {error: "No project store"} unless store
        deleted = store.clear_moment_feedback(event_id.to_i)
        {success: true, deleted: deleted}
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
        else
          scoped = ScopedFactResolver.scoped_ids_from_details(details)
          scoped.any? ? ScopedFactResolver.resolve(@manager, scoped) : []
        end

        # For recalls, "what triggered this" is high-signal context that the
        # raw event detail can't answer. Find the ingest immediately before
        # this recall so the modal can show the user prompt / assistant turn
        # that motivated the lookup. Time-window fallback when session_id is
        # absent (MCP tool calls don't thread session_id).
        trigger = (row[:event_type] == "recall") ? find_recall_trigger(store, row) : nil

        {
          event: event,
          content_item: content_item,
          linked_facts: linked_facts,
          trigger: trigger
        }.compact
      end

      # Find the hook_ingest event that most likely triggered a given recall.
      # Recall events often arrive from MCP tool calls without a session_id,
      # so we use time proximity: the last successful ingest before the recall
      # within a small window.
      TRIGGER_WINDOW_SECONDS = 600 # 10 min — a realistic session stretch

      def find_recall_trigger(store, recall_row)
        window_start = (Time.parse(recall_row[:occurred_at]) - TRIGGER_WINDOW_SECONDS).utc.iso8601
        dataset = store.activity_events
          .where(event_type: %w[hook_ingest hook_context])
          .where(status: "success")
          .where { occurred_at <= recall_row[:occurred_at] }
          .where { occurred_at >= window_start }

        if recall_row[:session_id]
          dataset = dataset.where(session_id: recall_row[:session_id])
        end

        row = dataset.order(Sequel.desc(:occurred_at)).first
        return nil unless row

        details = row[:detail_json] ? JSON.parse(row[:detail_json], symbolize_names: true) : {}
        content_item_id = details[:content_id] || details[:content_item_id]
        content = content_item_id ? load_content_item(store, content_item_id) : nil

        {
          event_id: row[:id],
          event_type: row[:event_type],
          occurred_at: row[:occurred_at],
          occurred_ago: Core::RelativeTime.format(row[:occurred_at]),
          session_id: row[:session_id],
          user_prompt: content ? extract_user_prompt(content[:raw_text_preview]) : nil,
          content_item: content
        }
      rescue ArgumentError, JSON::ParserError, Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("find_recall_trigger failed: #{e.message}")
        nil
      end

      # Claude Code transcripts are JSONL where each line is a user/assistant
      # turn. Extract the most recent *human* user message (not a tool_result
      # or Claude-Code command-stdout wrapper) so recall moments can show
      # "what the user asked" instead of raw JSONL.
      #
      # Filters out:
      # - tool_result entries (tool plumbing, not prompts)
      # - <local-command-*> / <command-*> tagged content (Claude Code shell ops)
      # - Blank / whitespace-only messages
      #
      # Returns nil on parse failure or when no human prompt is found.
      def extract_user_prompt(raw_text)
        return nil unless raw_text.is_a?(String) && !raw_text.empty?

        raw_text.split("\n").reverse_each do |line|
          next if line.strip.empty?
          begin
            turn = JSON.parse(line)
          rescue JSON::ParserError
            next
          end
          next unless turn.is_a?(Hash) && turn.dig("message", "role") == "user"

          content = turn.dig("message", "content")
          text = case content
          when String then content
          when Array
            content.filter_map { |c|
              next unless c.is_a?(Hash) && c["type"] == "text" && c["text"]
              c["text"]
            }.first
          end

          stripped = text.to_s.strip
          next if stripped.empty?
          next if plumbing_noise?(stripped)
          return stripped
        end
        nil
      end

      COMMAND_TAG_RE = /\A<(?:local-command-[a-z]+|command-(?:name|args|message|stdout|stderr))\b/i

      def plumbing_noise?(text)
        return true if text.match?(COMMAND_TAG_RE)
        return true if text.start_with?("[tool_") # tool_use / tool_result stringified
        false
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

      STALE_WINDOW_DAYS = 30

      def facts(params = {})
        scope = params["scope"] || "all"
        limit = (params["limit"] || 50).to_i
        offset = (params["offset"] || 0).to_i
        status_filter = params["status"] || "active"
        search = params["q"]
        stale_only = params["stale"] == "true"

        stores = facts_stores_for(scope)
        return {facts: [], total: 0, limit: limit, offset: offset, scope: scope} if stores.empty?

        # [scope, id] pairs seen in recent recalls. We exclude per-scope so
        # project fact #5 being recalled doesn't hide global fact #5 from
        # the stale view (and vice versa).
        stale_excluded_pairs = stale_only ? facts_seen_in_recent_recalls : []
        stale_excluded_by_scope = stale_excluded_pairs.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

        collected = stores.flat_map { |source, store|
          dataset = store.facts.where(status: status_filter)
          dataset = dataset.where(Sequel.like(:predicate, "%#{search}%") | Sequel.like(:object_literal, "%#{search}%")) if search && !search.empty?
          if stale_only
            excluded = stale_excluded_by_scope[source] || []
            dataset = dataset.exclude(id: excluded) if excluded.any?
          end
          rows = dataset.order(Sequel.desc(:created_at)).all
          presented = FactPresenter.new(store).list_summary(rows)
          presented.map { |f| f.merge(source: source) }
        }
        collected.sort_by! { |f| -Core::RelativeTime.to_epoch(f[:created_at]) }

        {
          total: collected.size,
          limit: limit,
          offset: offset,
          scope: scope,
          stale: stale_only,
          facts: Array(collected[offset, limit])
        }
      end

      # Aggregate scoped [scope, id] pairs that showed up in any successful
      # recall over the stale window. Used to exclude "has been recalled
      # recently" facts when the caller wants only the stale ones.
      # Returns pairs rather than bare IDs so project fact #1 and global
      # fact #1 don't collide.
      def facts_seen_in_recent_recalls
        store = default_store
        return [] unless store
        cutoff = (Time.now.utc - STALE_WINDOW_DAYS * 86_400).iso8601
        pairs = Set.new
        store.activity_events
          .where(event_type: "recall", status: "success")
          .where { occurred_at >= cutoff }
          .select(:detail_json)
          .all
          .each do |row|
            details = row[:detail_json] ? JSON.parse(row[:detail_json]) : {}
            scoped = ScopedFactResolver.scoped_ids_from_details(details)
            ScopedFactResolver.flat_pairs(scoped).each { |pair| pairs << pair }
          end
        pairs.to_a
      rescue Sequel::DatabaseError, JSON::ParserError => e
        ClaudeMemory.logger.debug("facts_seen_in_recent_recalls failed: #{e.message}")
        []
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
        Timeline.new(@manager).days
      end

      def telemetry
        Telemetry.new(@manager).snapshot
      end

      def prompt_journey(prompt_id)
        PromptJourney.new(@manager).for(prompt_id.to_s)
      end

      private

      CONTENT_ITEM_PREVIEW_BYTES = 8000

      def serialize_feedback(row)
        return nil unless row
        {
          event_id: row[:event_id],
          verdict: row[:verdict],
          note: row[:note],
          recorded_at: row[:recorded_at],
          recorded_ago: Core::RelativeTime.format(row[:recorded_at])
        }
      end

      # Recall returns results in the shape {fact:, receipts:, source:} —
      # the fact sub-hash carries the actual fields (subject_name, predicate,
      # object_literal, scope, ...). Receipts are the provenance chain.
      # We flatten to the dashboard's expected shape and surface the
      # receipts count so users can see "this had 27 supporting quotes"
      # at a glance without drilling in.
      def serialize_recall_fact(result)
        fact = result[:fact] || result["fact"] || result
        receipts = result[:receipts] || result["receipts"] || []
        source = result[:source] || result["source"]

        {
          id: fact[:id] || fact["id"],
          docid: fact[:docid] || fact["docid"],
          subject: fact[:subject_name] || fact["subject_name"] || fact[:subject] || fact["subject"],
          predicate: fact[:predicate] || fact["predicate"],
          object: fact[:object_literal] || fact["object_literal"] || fact[:object] || fact["object"],
          scope: fact[:scope] || fact["scope"],
          source: source.to_s,
          score: fact[:score] || fact["score"],
          confidence: fact[:confidence] || fact["confidence"],
          created_at: fact[:created_at] || fact["created_at"],
          receipts_count: receipts.is_a?(Array) ? receipts.size : nil
        }.compact
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
    end
  end
end
