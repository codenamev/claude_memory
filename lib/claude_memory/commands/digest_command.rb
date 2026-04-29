# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Weekly digest — a markdown summary of what memory did over the last N days.
    # Rolls up moment counts, new knowledge, utilization, conflicts, and user
    # feedback so users can see the value memory is delivering without
    # needing to visit the dashboard.
    #
    # The data it aggregates all already exists (activity_events, facts,
    # conflicts, moment_feedback); this command only shapes it into a report.
    class DigestCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {since_days: 7, output: nil}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory digest [options]"
            parser.on("--since DAYS", Integer, "Coverage window in days (default: 7)") { |v| o[:since_days] = v }
            parser.on("--output FILE", "Write to file instead of stdout") { |v| o[:output] = v }
          end
        end
        return 1 if opts.nil?
        return failure("--since must be positive") if opts[:since_days] <= 0

        manager = Store::StoreManager.new
        report = render_report(manager, opts[:since_days])
        manager.close

        if opts[:output]
          File.write(opts[:output], report)
          stderr.puts "Wrote digest to #{opts[:output]}"
        else
          stdout.puts report
        end

        0
      end

      private

      def render_report(manager, days)
        cutoff = (Time.now.utc - days * 86_400).iso8601
        lines = []
        lines << "# ClaudeMemory Digest"
        lines << ""
        lines << "_Coverage: last #{days} day#{"s" unless days == 1} (since #{cutoff})_"
        lines << ""
        lines << activity_section(manager, cutoff)
        lines << ""
        lines << context_cost_section(manager)
        lines << ""
        lines << knowledge_section(manager, cutoff)
        lines << ""
        lines << utilization_section(manager)
        lines << ""
        lines << conflicts_section(manager)
        lines << ""
        lines << feedback_section(manager, cutoff)
        lines.join("\n") + "\n"
      end

      def activity_section(manager, cutoff)
        store = manager.default_store(prefer: :project)
        return "## Activity\n\n_No project database._" unless store

        by_kind = store.activity_events
          .where { occurred_at >= cutoff }
          .group_and_count(:event_type)
          .all
          .to_h { |r| [r[:event_type], r[:count]] }

        total = by_kind.values.sum
        out = ["## Activity", ""]
        out << "**Moments recorded:** #{total}"
        out << ""
        if total.zero?
          out << "_No activity in this window._"
        else
          %w[recall store_extraction hook_context hook_ingest hook_sweep].each do |event_type|
            count = by_kind[event_type] || 0
            next if count.zero?
            out << "- #{humanize_event(event_type)}: #{count}"
          end
        end
        out.join("\n")
      rescue Sequel::DatabaseError => e
        "## Activity\n\n_Unavailable: #{e.message}_"
      end

      def humanize_event(event_type)
        case event_type
        when "recall" then "Recalls"
        when "store_extraction" then "Facts extracted"
        when "hook_context" then "Context injections"
        when "hook_ingest" then "Transcripts ingested"
        when "hook_sweep" then "Maintenance sweeps"
        else event_type
        end
      end

      def knowledge_section(manager, cutoff)
        out = ["## New knowledge", ""]
        counts = {}
        %w[project global].each do |scope|
          store = manager.store_if_exists(scope)
          next unless store
          store.facts
            .where(status: "active")
            .where { created_at >= cutoff }
            .group_and_count(:predicate)
            .all
            .each { |r| counts[r[:predicate]] = (counts[r[:predicate]] || 0) + r[:count] }
        end

        if counts.empty?
          out << "_No new facts in this window._"
        else
          total = counts.values.sum
          out << "**New active facts:** #{total}"
          out << ""
          counts.sort_by { |_, c| -c }.each { |predicate, count| out << "- #{predicate}: #{count}" }
        end
        out.join("\n")
      rescue Sequel::DatabaseError => e
        "## New knowledge\n\n_Unavailable: #{e.message}_"
      end

      # The token cost of every SessionStart context injection, measured over
      # the last 30 days (Trust panel's window — intentionally wider than the
      # digest's coverage window so percentiles stay statistically meaningful
      # on quiet weeks). Reports zero state explicitly so users know whether a
      # missing number means "no injections" vs. "telemetry didn't fire".
      def context_cost_section(manager)
        tb = Dashboard::Trust.new(manager).token_budget
        out = ["## Context cost", ""]
        if tb[:sample_size].zero?
          out << "_No context injections in the last #{tb[:window_days]} days._"
        else
          out << "**Per-session injected tokens (last #{tb[:window_days]}d, n=#{tb[:sample_size]}):**"
          out << "- p50: #{tb[:p50]} tokens"
          out << "- p95: #{tb[:p95]} tokens"
          out << "- avg: #{tb[:avg]} tokens"
        end
        out.join("\n")
      rescue Sequel::DatabaseError => e
        "## Context cost\n\n_Unavailable: #{e.message}_"
      end

      def utilization_section(manager)
        util = Dashboard::Trust.new(manager).utilization
        pct = util[:ratio_pct]
        <<~SECTION.strip
          ## Utilization

          **Ratio (last #{util[:window_days]}d):** #{pct}%
          - Extracted: #{util[:extracted]}
          - Used (of those extracted): #{util[:used_from_extracted]}
          - Total fact uses across recalls + injections: #{util[:used]}
        SECTION
      end

      def conflicts_section(manager)
        counts = Dashboard::Conflicts.new(manager).distinct_open_counts
        total = counts[:total]
        out = ["## Conflicts", ""]
        if total.zero?
          out << "_No open conflicts._"
        else
          out << "**Open contradictions:** #{total} distinct"
          out << "- Project: #{counts[:project]}"
          out << "- Global: #{counts[:global]}"
        end
        out.join("\n")
      rescue Sequel::DatabaseError => e
        "## Conflicts\n\n_Unavailable: #{e.message}_"
      end

      def feedback_section(manager, cutoff)
        store = manager.default_store(prefer: :project)
        return "## Feedback\n\n_No project database._" unless store

        rows = store.moment_feedback.where { recorded_at >= cutoff }.all
        up = rows.count { |r| r[:verdict] == "up" }
        down = rows.count { |r| r[:verdict] == "down" }
        total = up + down

        out = ["## Feedback", ""]
        if total.zero?
          out << "_No thumbs in this window._"
        else
          ratio = ((up.to_f / total) * 100).round
          out << "**Moments rated:** #{total}"
          out << "- 👍 Up: #{up}"
          out << "- 👎 Down: #{down}"
          out << "- Positive ratio: #{ratio}%"
        end
        out.join("\n")
      rescue Sequel::DatabaseError => e
        "## Feedback\n\n_Unavailable: #{e.message}_"
      end
    end
  end
end
