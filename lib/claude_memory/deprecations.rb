# frozen_string_literal: true

module ClaudeMemory
  # Soft-rename / soft-removal mechanism for public-API surfaces.
  # Used to mark an old name (CLI flag, MCP tool, Ruby method, hook
  # field, predicate) as deprecated in `N.x.0` releases while keeping it
  # functional for at least one minor cycle, with explicit removal no
  # earlier than `(N+1).0.0`. This deprecation policy is documented in
  # `docs/api_stability.md`.
  #
  # @example Deprecate a renamed CLI flag
  #   ClaudeMemory::Deprecations.warn(
  #     name: "claude-memory recall --legacy-mode",
  #     replacement: "--mode=legacy",
  #     removed_in: "1.0.0"
  #   )
  #
  # @example Deprecate a soft-renamed Ruby method
  #   ClaudeMemory::Deprecations.warn(
  #     name: "ClaudeMemory::Recall#legacy_query",
  #     replacement: "Recall#query",
  #     removed_in: "1.0.0",
  #     message: "Pass `mode: :legacy` to #query instead."
  #   )
  #
  # Two suppression mechanisms keep deprecation noise manageable:
  #
  # - **Per-call-site dedupe**: same (name, caller_file:line) pair only
  #   emits once per process. Prevents tight loops or repeated callers
  #   from drowning the terminal.
  # - **Env var opt-out**: `CLAUDE_MEMORY_NO_DEPRECATIONS=1` silences
  #   everything. Recommended for test fixtures and CI runs that
  #   knowingly exercise legacy paths.
  module Deprecations
    ENV_OPT_OUT = "CLAUDE_MEMORY_NO_DEPRECATIONS"

    # Tracks already-emitted (name, caller-location) pairs for dedupe.
    # Bounded — this is a long-lived process state but the cardinality
    # is at most "every deprecated surface × every call site that
    # touches it", which stays small in practice.
    @emitted = {}
    @mutex = Mutex.new

    class << self
      # Emit a deprecation warning to `output` (stderr by default).
      #
      # @param name [String] the deprecated identifier (CLI flag, method,
      #   tool name, etc.). Be specific: "ClaudeMemory::Recall#query(:legacy)"
      #   beats "Recall#query".
      # @param replacement [String, nil] what users should switch to.
      #   Optional but strongly recommended — a deprecation without a
      #   migration path is annoying.
      # @param removed_in [String, nil] target removal version, semver
      #   string. Conventionally the next major (`(N+1).0.0`).
      # @param message [String, nil] free-form extra context. Use for
      #   subtle migration nuance the replacement string can't capture.
      # @param caller_location [String, nil] override for testing.
      # @param output [IO] override for testing. Default: $stderr.
      # @return [Boolean] true if a warning was emitted, false if
      #   suppressed (env opt-out or already-emitted dedupe).
      def warn(name:, replacement: nil, removed_in: nil, message: nil,
        caller_location: nil, output: $stderr)
        return false if suppressed?

        location = caller_location || derive_caller_location
        key = "#{name}@#{location}"

        @mutex.synchronize do
          return false if @emitted[key]
          @emitted[key] = true
        end

        output.puts(format_warning(name: name, replacement: replacement,
          removed_in: removed_in, message: message, location: location))
        true
      end

      # Wipe the per-call-site dedupe state. Test-only — production
      # callers should rely on the per-process behavior.
      def reset!
        @mutex.synchronize { @emitted.clear }
      end

      private

      def suppressed?
        ENV[ENV_OPT_OUT] == "1"
      end

      def derive_caller_location
        # Skip: 0=this method, 1=warn, 2=actual caller
        loc = caller_locations(3, 1)&.first
        loc ? "#{loc.path}:#{loc.lineno}" : "unknown"
      end

      def format_warning(name:, replacement:, removed_in:, message:, location:)
        parts = ["[ClaudeMemory] DEPRECATION: #{name} is deprecated"]
        parts << "scheduled for removal in #{removed_in}" if removed_in
        parts << "use #{replacement} instead" if replacement
        head = parts.join(", ") + "."
        head += " #{message}" if message
        "#{head} (called from #{location})"
      end
    end
  end
end
