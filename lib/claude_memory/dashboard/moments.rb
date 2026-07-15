# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Dashboard
    # Turns the flat activity_events log into enriched "moments" — the user-visible
    # primitive for the feed-first dashboard. Each moment inlines the data needed
    # to render its card (content preview, linked facts, resolved top_fact_ids)
    # so the client never needs a second round trip per row.
    #
    # A moment's {:kind} is a stable narrative category the client uses to pick
    # a card renderer. It's derived from event_type + status so the client
    # doesn't have to re-derive the same mapping.
    class Moments
      DEFAULT_LIMIT = 50
      CONTENT_PREVIEW_BYTES = 800
      FEED_EVENT_TYPES = %w[hook_context recall store_extraction hook_ingest hook_sweep].freeze

      # Kind → underlying event_type(s). Used to pull only relevant rows from
      # the DB when the caller specifies kinds; without this, a noisy stream
      # of ingests pushes the value moments past the query limit.
      KIND_TO_EVENT_TYPES = {
        "context_injection" => %w[hook_context],
        "context_skipped" => %w[hook_context],
        "recall_hit" => %w[recall],
        "recall_empty" => %w[recall],
        "extraction" => %w[store_extraction],
        "ingest" => %w[hook_ingest],
        "ingest_skipped" => %w[hook_ingest],
        "sweep" => %w[hook_sweep]
      }.freeze

      # Moment kinds whose detail carries scoped top-fact IDs to resolve.
      SCOPED_FACT_KINDS = %w[context_injection recall_hit recall_empty].freeze

      def initialize(manager)
        @manager = manager
      end

      # @param params [Hash]
      #   "limit" — max moments (default 50, clamped 1..200)
      #   "before" — ISO 8601 cursor; return moments strictly older than this
      #   "kinds" — comma-separated kinds to include (default: all feed kinds)
      def list(params = {})
        store = default_store
        return empty_response unless store

        limit = (params["limit"] || DEFAULT_LIMIT).to_i.clamp(1, 200)
        before = params["before"]
        kinds = parse_kinds(params["kinds"])

        event_types = resolve_event_types(kinds)
        dataset = store.activity_events
          .where(event_type: event_types)
          .order(Sequel.desc(:occurred_at))
        dataset = dataset.where { occurred_at < before } if before && !before.empty?

        # Fetch up to 2x limit so per-kind filtering still produces a full
        # page (e.g. recall_hit vs recall_empty both live under event_type=recall).
        rows = dataset.limit(limit * 2).all
        events = rows.map { |r|
          r[:details] = r[:detail_json] ? JSON.parse(r[:detail_json], symbolize_names: true) : nil
          r.delete(:detail_json)
          r
        }

        # Preload content previews + extracted facts for every extraction/ingest
        # event in one query each, so build_moment doesn't fire a per-row
        # content_items lookup + facts⋈provenance join (was ~2 queries × up to
        # 2×limit rows).
        content_ids = content_item_ids_for(events)
        content_by_id = batch_content(store, content_ids)
        facts_by_content = batch_extracted_facts(store, content_ids)

        # Preload scoped top-facts for every recall/context event in one query
        # per scope (was a per-row facts + entities lookup in resolve_scoped_facts).
        scoped_details = events.filter_map { |e| e[:details] if SCOPED_FACT_KINDS.include?(kind_for(e)) }
        fact_index = ScopedFactResolver.build_fact_index(@manager, ScopedFactResolver.merge_scoped_ids(scoped_details))

        moments = events.map { |e| build_moment(store, e, content_by_id, facts_by_content, fact_index) }
        moments = moments.select { |m| kinds.include?(m[:kind]) } unless kinds.empty?
        has_more = moments.size > limit
        moments = moments.first(limit)
        attach_feedback(store, moments)

        {
          moments: moments,
          next_before: moments.last&.dig(:occurred_at),
          has_more: has_more
        }
      end

      private

      # When no kinds are specified, pull all feed event types. When kinds
      # are specified, union the event_types they map to so the DB query
      # only loads the relevant rows.
      def resolve_event_types(kinds)
        return FEED_EVENT_TYPES if kinds.empty?
        kinds.flat_map { |k| KIND_TO_EVENT_TYPES.fetch(k, []) }.uniq
      end

      def empty_response
        {moments: [], next_before: nil, has_more: false}
      end

      def parse_kinds(raw)
        return [] if raw.nil? || raw.empty?
        raw.split(",").map(&:strip).reject(&:empty?)
      end

      def default_store
        @manager.default_store(prefer: :project)
      end

      # Stable narrative kinds drive card rendering on the client. Keep this
      # map small; any edge case becomes "event" with the raw detail exposed.
      def kind_for(event)
        case event[:event_type]
        when "hook_context"
          (event[:status] == "success") ? "context_injection" : "context_skipped"
        when "recall"
          details = event[:details] || {}
          if (details[:result_count] || 0).zero?
            "recall_empty"
          else
            "recall_hit"
          end
        when "store_extraction"
          "extraction"
        when "hook_ingest"
          (event[:status] == "success") ? "ingest" : "ingest_skipped"
        when "hook_sweep"
          "sweep"
        else
          "event"
        end
      end

      def build_moment(store, event, content_by_id, facts_by_content, fact_index)
        details = event[:details] || {}
        kind = kind_for(event)
        base = {
          id: event[:id],
          event_type: event[:event_type],
          status: event[:status],
          kind: kind,
          occurred_at: event[:occurred_at],
          occurred_ago: Core::RelativeTime.format(event[:occurred_at]),
          session_id: event[:session_id],
          duration_ms: event[:duration_ms],
          details: details
        }

        enrich(base, kind, details, content_by_id, facts_by_content, fact_index)
      end

      def enrich(moment, kind, details, content_by_id, facts_by_content, fact_index)
        case kind
        when "context_injection"
          moment.merge(
            context_preview: details[:preview],
            context_length: details[:context_length],
            fact_count: details[:fact_count] || (details[:top_fact_ids] || []).size,
            top_subjects: details[:top_subjects] || [],
            top_facts: ScopedFactResolver.resolve_from_index(details, fact_index),
            truncated: details[:truncated]
          )
        when "recall_hit", "recall_empty"
          moment.merge(
            tool: details[:tool],
            query: details[:query],
            result_count: details[:result_count] || 0,
            scope: details[:scope],
            top_facts: ScopedFactResolver.resolve_from_index(details, fact_index),
            results_by_scope: details[:results_by_scope]
          )
        when "extraction"
          cid = (details[:content_item_id] || details[:content_id])&.to_i
          moment.merge(
            tool: details[:tool],
            facts_created: details[:facts_created] || 0,
            entities_created: details[:entities_created] || 0,
            content_item: content_by_id[cid],
            extracted_facts: facts_by_content[cid] || []
          )
        when "ingest"
          cid = details[:content_id]&.to_i
          moment.merge(
            bytes_read: details[:bytes_read],
            content_item: content_by_id[cid],
            extracted_facts: facts_by_content[cid] || []
          )
        when "ingest_skipped"
          moment.merge(reason: details[:reason])
        when "sweep"
          moment.merge(
            elapsed_seconds: details[:elapsed_seconds],
            budget_honored: details[:budget_honored]
          )
        else
          moment
        end
      end

      # Collect the distinct content_item ids referenced by extraction/ingest
      # events, so their content + facts can be batch-loaded once per page.
      def content_item_ids_for(events)
        events.filter_map { |e|
          details = e[:details] || {}
          case kind_for(e)
          when "extraction" then details[:content_item_id] || details[:content_id]
          when "ingest" then details[:content_id]
          end
        }.map(&:to_i).uniq
      end

      # id => content preview hash, loaded in one query.
      def batch_content(store, ids)
        return {} if ids.empty?
        store.content_items.where(id: ids).all.each_with_object({}) do |row, h|
          h[row[:id]] = content_preview(row)
        end
      rescue Sequel::DatabaseError
        {}
      end

      def content_preview(row)
        raw = row[:raw_text].to_s
        truncated = raw.bytesize > CONTENT_PREVIEW_BYTES
        {
          id: row[:id],
          source: row[:source],
          session_id: row[:session_id],
          byte_len: row[:byte_len],
          occurred_at: row[:occurred_at],
          preview: truncated ? raw.byteslice(0, CONTENT_PREVIEW_BYTES) : raw,
          truncated: truncated
        }
      end

      def attach_feedback(store, moments)
        return if moments.empty?
        ids = moments.map { |m| m[:id] }
        feedback_by_event = store.moment_feedback.where(event_id: ids).all.each_with_object({}) do |row, h|
          h[row[:event_id]] = {
            verdict: row[:verdict],
            note: row[:note],
            recorded_at: row[:recorded_at]
          }
        end
        moments.each do |m|
          m[:feedback] = feedback_by_event[m[:id]]
        end
      rescue Sequel::DatabaseError
        # Table missing on older DBs — skip silently.
      end

      # content_item_id => [fact summaries], loaded in one join keyed by the
      # provenance content_item_id (tagged as __cid, stripped before presenting).
      def batch_extracted_facts(store, ids)
        return {} if ids.empty?
        rows = store.db[:facts]
          .join(:provenance, fact_id: :id)
          .where(Sequel[:provenance][:content_item_id] => ids)
          .select(Sequel[:facts].*, Sequel[:provenance][:content_item_id].as(:__cid))
          .all
        presenter = FactPresenter.new(store)
        rows.group_by { |r| r[:__cid] }.transform_values do |group|
          group.each { |r| r.delete(:__cid) }
          presenter.list_summary(group)
        end
      rescue Sequel::DatabaseError
        {}
      end
    end
  end
end
