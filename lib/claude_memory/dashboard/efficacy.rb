# frozen_string_literal: true

module ClaudeMemory
  module Dashboard
    module Efficacy
      # Pure report calculator for recall activity events. Takes a list of
      # already-loaded events and produces the shaped metrics the dashboard
      # renders. No I/O, no database access — separating compute from
      # loading keeps the aggregation fast-testable and portable across
      # event sources.
      #
      # Expected event shape (matches {ClaudeMemory::ActivityLog.recent} output):
      #
      #   {
      #     id:, event_type:, status:, duration_ms:, session_id:,
      #     occurred_at:, details: {tool:, query:, result_count:,
      #                             results_by_scope: {"project" => N, "global" => M}, ...}
      #   }
      module Reporter
        RECALL_TRACE_LIMIT = 50
        MEMORY_GAPS_LIMIT = 10

        module_function

        # @param events [Array<Hash>] recall activity events (post-filter)
        # @param timeframe [Hash] {since:, session_id:} echoed into the response
        # @return [Hash] the efficacy payload
        def report(events, timeframe: {})
          result_counts = events.map { |e| e.dig(:details, :result_count) || 0 }
          latencies = events.map { |e| e[:duration_ms] }.compact
          successful = events.count { |e| e[:status] == "success" && (e.dig(:details, :result_count) || 0) > 0 }
          empty = events.count { |e| e[:status] == "success" && (e.dig(:details, :result_count) || 0) == 0 }

          {
            timeframe: {since: timeframe[:since], session_id: timeframe[:session_id]},
            recall_events: events.size,
            successful_recalls: successful,
            empty_recalls: empty,
            hit_rate: percentage(successful, events.size),
            total_results_served: result_counts.sum,
            median_results_per_query: median(result_counts),
            median_latency_ms: median(latencies),
            tool_mix: tool_mix(events),
            source_contribution: source_contribution(events),
            memory_gaps: memory_gaps(events),
            recall_trace: recall_trace(events)
          }
        end

        # Percentage with zero-safe denominator, rounded to 1 decimal.
        def percentage(part, whole)
          return 0 if whole.to_i.zero?
          (part.to_f / whole * 100).round(1)
        end

        # Sorted median — returns 0 for empty input, midpoint average for even counts.
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

        # Aggregate {results_by_scope} across events. Reveals where returned
        # facts actually came from — the one question only efficacy can answer.
        def source_contribution(events)
          totals = Hash.new(0)
          events.each do |e|
            by_scope = e.dig(:details, :results_by_scope)
            next unless by_scope.is_a?(Hash)
            by_scope.each { |scope, n| totals[scope.to_s] += n.to_i }
          end
          totals.empty? ? [] : totals.map { |scope, count| {scope: scope, count: count} }.sort_by { |r| -r[:count] }
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
      end
    end
  end
end
