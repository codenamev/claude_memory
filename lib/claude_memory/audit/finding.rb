# frozen_string_literal: true

module ClaudeMemory
  module Audit
    # A single audit finding. Immutable value object emitted by checks
    # (see Audit::Checks) and aggregated by Audit::Runner.
    #
    # Severity levels:
    #   - :error — a contract violation; CI/automation should fail
    #   - :warn  — likely problem requiring attention but not blocking
    #   - :info  — observation; suggests an optimization or cleanup
    #
    # Each finding embeds the suggested remediation command(s) as plain
    # strings so the audit output is directly actionable. The skill
    # `/audit-memory` reads these and offers to run them for the user.
    Finding = Data.define(:id, :severity, :title, :detail, :suggestion, :fact_ids) do
      def error? = severity == :error
      def warn? = severity == :warn
      def info? = severity == :info

      def to_h
        {
          id: id,
          severity: severity,
          title: title,
          detail: detail,
          suggestion: suggestion,
          fact_ids: fact_ids
        }
      end
    end
  end
end
