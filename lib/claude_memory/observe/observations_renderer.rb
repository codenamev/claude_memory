# frozen_string_literal: true

module ClaudeMemory
  module Observe
    # Renders episodic observation rows into the actor-facing markdown block —
    # the front-loaded "what happened" log that complements the fact snapshot
    # ("what is true").
    #
    # Priority is an internal Observer/Reflector signal. Following Mastra, only
    # 🔴 (important) survives as a marker when shown to the actor; 🟡/🟢 are
    # stripped as visual noise. The observation bodies themselves are always
    # shown — the emoji is the only thing filtered.
    module ObservationsRenderer
      IMPORTANT_MARKER = "🔴"

      module_function

      # @param observations [Array<Hash>] rows with :body, :priority, :observed_at
      # @param title [String] section heading
      # @param intro [Boolean] include the one-line explainer (true for injection)
      # @return [String, nil] markdown block, or nil when there is nothing to show
      def render(observations, title: "Observations (what happened)", intro: true)
        rows = Array(observations).reject { |o| o[:body].to_s.strip.empty? }
        return nil if rows.empty?

        lines = ["## #{title}"]
        if intro
          lines << ""
          lines << "Episodic log of what happened in this project — complements the facts above (what is true). Newest first."
        end
        lines << ""
        rows.each { |obs| lines << format_line(obs) }
        lines.join("\n")
      end

      # @return [String] a single "- [🔴 ]body (time ago)" log line
      def format_line(obs)
        body = obs[:body].to_s.strip
        marker = (obs[:priority] == Domain::Observation::IMPORTANT) ? "#{IMPORTANT_MARKER} " : ""
        ago = Core::RelativeTime.format(obs[:observed_at])
        suffix = ago ? " (#{ago})" : ""
        "- #{marker}#{body}#{suffix}"
      end
    end
  end
end
