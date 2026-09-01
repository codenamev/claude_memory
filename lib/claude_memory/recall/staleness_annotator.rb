# frozen_string_literal: true

require "time"

module ClaudeMemory
  class Recall
    # Pure function. Given a fact hash, returns a human-readable staleness
    # marker for single-value facts that are old and unconfirmed, or nil.
    #
    # Single-value predicates (uses_database / deployment_platform /
    # auth_method) are exclusive claims — "the project uses X." Claude
    # follows them authoritatively, so a *stale* single-value fact is the
    # most dangerous kind of memory: the 0.12 harm benchmark caught Claude
    # emitting `git push heroku` from a stale deployment_platform fact with
    # no hedge (docs/1_0_punchlist.md #3 / #15). This annotator surfaces the
    # uncertainty inline at context-injection time so Claude can hedge or
    # verify instead of blindly following.
    #
    # Multi-value predicates (convention, decision, uses_framework, …) are
    # NOT annotated: they accumulate, so one stale entry doesn't carry the
    # same authoritative weight, and flagging them would just add noise.
    #
    # A fact is stale-for-injection when BOTH hold:
    #   - the claim is old: valid_from (or created_at fallback) is older
    #     than threshold_days — a freshly recorded fact is never stale even
    #     if it describes something historical, and
    #   - it hasn't been confirmed recently: last_recalled_at is null or
    #     older than threshold_days — a fact that's been recalled lately is
    #     implicitly re-validated by use.
    #
    # No side effects; safe to call per-fact in the context-injection loop.
    module StalenessAnnotator
      module_function

      DEFAULT_THRESHOLD_DAYS = 180

      # @param fact [Hash] needs :predicate; reads :status, :valid_from,
      #   :created_at, :last_recalled_at, :expiring_since when present
      # @param now [Time]
      # @param threshold_days [Integer]
      # @return [String, nil] marker text, or nil when not stale / not guarded
      def marker_for(fact, now: Time.now.utc, threshold_days: DEFAULT_THRESHOLD_DAYS)
        # Lifecycle state (#14) outranks the heuristic staleness guess: an
        # expiring fact is one the sweeper has already judged unratified, so
        # it's flagged on every predicate, not just single-value ones —
        # this marker is the ratification prompt.
        expiring = expiring_marker(fact, now: now)
        return expiring if expiring

        return nil unless Resolve::PredicatePolicy.single?(fact[:predicate].to_s)

        established = parse_time(fact[:valid_from]) || parse_time(fact[:created_at])
        return nil unless established

        cutoff = now - threshold_days * 86_400
        return nil unless established < cutoff

        last_seen = parse_time(fact[:last_recalled_at])
        return nil if last_seen && last_seen >= cutoff

        months = ((now - established) / (30 * 86_400)).round
        "⚠ stale: recorded #{established.strftime("%Y-%m-%d")}, " \
          "not confirmed in ~#{months}mo — verify before relying"
      end

      # @return [Boolean] true when marker_for would return a marker
      def stale?(fact, now: Time.now.utc, threshold_days: DEFAULT_THRESHOLD_DAYS)
        !marker_for(fact, now: now, threshold_days: threshold_days).nil?
      end

      # @return [String, nil] marker for facts in the expiring lifecycle
      #   state, or nil for any other status
      def expiring_marker(fact, now: Time.now.utc)
        return nil unless fact[:status].to_s == "expiring"

        since = parse_time(fact[:expiring_since])
        days = since ? ((now - since) / 86_400).round : nil
        age = days ? " #{days}d ago" : ""
        "⏳ expiring: unratified#{age} — reaffirm if still true, or let it expire"
      end

      def parse_time(value)
        return nil if value.nil?
        return value.utc if value.is_a?(Time)
        Time.parse(value.to_s).utc
      rescue ArgumentError
        nil
      end
    end
  end
end
