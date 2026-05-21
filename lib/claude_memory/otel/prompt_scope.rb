# frozen_string_literal: true

module ClaudeMemory
  module OTel
    # Back-tags activity_events with the OTel prompt.id after telemetry
    # events arrive. Hook events (hook_ingest, hook_context, ...) fire
    # ~immediately as the user's turn closes, but Claude Code batches OTel
    # exports on the OTEL_METRIC_EXPORT_INTERVAL (default 60s), so by the
    # time we see a prompt.id on the receiver, the activity_events for that
    # turn already exist with prompt_id = NULL.
    #
    # Tagging strategy per (prompt_id, session_id) group:
    #   1. session_id-match path — for activity_events carrying the same
    #      session_id, update those that fall in the prompt's time window.
    #      Hook events (hook_ingest, hook_context, hook_sweep, hook_publish,
    #      roi_nudge) reliably carry session_id from the Claude Code hook
    #      payload.
    #   2. time-window path — for activity_events with NULL session_id
    #      (recall, store_extraction — MCP-originated; Claude Code doesn't
    #      thread session_id into plugin MCP calls per reference_mcp_session
    #      _id_gap), tag by occurred_at falling in the prompt window only.
    #
    # Operates on both project_store and global_store when available.
    # Cross-project tagging (projects other than the dashboard's loaded one)
    # is out of scope — dashboard is per-project and other project DBs
    # aren't in the manager.
    class PromptScope
      # Bound the prompt window so a long-running turn doesn't sweep up
      # later activity events that belong to the NEXT prompt. The OTel
      # spec only emits prompt.id between user_prompt and the next
      # user_prompt, so the natural max is implicit; we add a safety
      # ceiling.
      MAX_WINDOW_SECONDS = 600
      # Buffer added after the latest OTel event because hook_ingest fires
      # AFTER the Stop event, which can be a few seconds after the last
      # api_request.
      POST_WINDOW_BUFFER_SECONDS = 30

      def initialize(manager)
        @manager = manager
      end

      # @param events [Array<Hash>] just-persisted OTel event rows
      #   (each carrying :prompt_id, :session_id, :occurred_at) — the
      #   same shape OtlpJsonEnvelope.parse_logs returns.
      # @return [Hash] {tagged: count, groups: count}
      def tag(events)
        return {tagged: 0, groups: 0} if events.nil? || events.empty?

        groups = group_by_prompt(events)
        return {tagged: 0, groups: 0} if groups.empty?

        tagged = 0
        groups.each do |key, range|
          prompt_id, session_id = key
          [@manager.project_store, @manager.global_store].compact.each do |store|
            tagged += tag_in_store(store, prompt_id, session_id, range)
          end
        end
        {tagged: tagged, groups: groups.size}
      rescue Sequel::DatabaseError => e
        ClaudeMemory.logger.debug("prompt_scope tag failed: #{e.message}")
        {tagged: 0, groups: 0, error: e.message}
      end

      private

      # Returns {[prompt_id, session_id_or_nil] => (lo..hi)} where lo/hi
      # are ISO 8601 strings derived from event occurred_at values.
      def group_by_prompt(events)
        events
          .select { |e| e[:prompt_id] && !e[:prompt_id].to_s.empty? }
          .group_by { |e| [e[:prompt_id], e[:session_id]] }
          .each_with_object({}) do |(key, group), out|
            timestamps = group.map { |e| e[:occurred_at] }.compact.sort
            next if timestamps.empty?
            lo = timestamps.first
            hi = (Time.parse(timestamps.last) + POST_WINDOW_BUFFER_SECONDS).utc.iso8601
            # Cap window length to MAX_WINDOW_SECONDS so a stale event
            # batch can't sweep a wide range.
            ceiling = (Time.parse(lo) + MAX_WINDOW_SECONDS).utc.iso8601
            hi = [hi, ceiling].min
            out[key] = (lo..hi)
          end
      end

      def tag_in_store(store, prompt_id, session_id, range)
        return 0 unless store&.db&.table_exists?(:activity_events)
        return 0 unless store.activity_events.columns.include?(:prompt_id)

        tagged_by_session = 0
        if session_id && !session_id.to_s.empty?
          tagged_by_session = store.activity_events
            .where(session_id: session_id, prompt_id: nil)
            .where { (occurred_at >= range.first) & (occurred_at <= range.last) }
            .update(prompt_id: prompt_id)
        end

        tagged_by_window = store.activity_events
          .where(session_id: nil, prompt_id: nil)
          .where { (occurred_at >= range.first) & (occurred_at <= range.last) }
          .update(prompt_id: prompt_id)

        tagged_by_session + tagged_by_window
      end
    end
  end
end
