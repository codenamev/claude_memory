# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Classifies MCP tool errors into three tiers with structured responses.
    #
    # Benign: Empty results, first use, database not yet initialized.
    #   No error surfaced — return helpful guidance instead.
    #
    # Retryable: Database locked, temporary I/O, connection reset.
    #   Tool failed but may succeed on retry.
    #
    # Fatal: Schema corruption, invalid parameters, programming bugs.
    #   Requires user intervention to resolve.
    #
    # Source: supermemory src/lib/error-helpers.js:1-72
    module ErrorClassifier
      SEVERITY_BENIGN = "benign"
      SEVERITY_RETRYABLE = "retryable"
      SEVERITY_FATAL = "fatal"

      # Errors that indicate temporary/transient failures
      RETRYABLE_ERROR_NAMES = %w[
        Sequel::DatabaseConnectionError
        Extralite::BusyError
      ].freeze

      RETRYABLE_ERROR_CLASSES = [
        Errno::EACCES,
        Errno::EAGAIN,
        IOError
      ].freeze

      # Errors that indicate permanent/programming failures
      FATAL_ERROR_CLASSES = [
        Errno::ENOSPC,
        Errno::EROFS,
        TypeError,
        NoMethodError,
        ArgumentError
      ].freeze

      module_function

      def classify(error)
        if retryable?(error)
          SEVERITY_RETRYABLE
        elsif fatal?(error)
          SEVERITY_FATAL
        elsif database_error?(error)
          # Generic database errors default to retryable
          SEVERITY_RETRYABLE
        else
          # Unknown errors default to fatal to surface issues
          SEVERITY_FATAL
        end
      end

      def build_error_response(error, tool_name: nil)
        severity = classify(error)

        case severity
        when SEVERITY_RETRYABLE
          {
            error: "Temporary failure",
            severity: SEVERITY_RETRYABLE,
            message: retryable_message(error),
            tool: tool_name,
            retry: true
          }
        when SEVERITY_FATAL
          {
            error: "Operation failed",
            severity: SEVERITY_FATAL,
            message: fatal_message(error),
            tool: tool_name,
            retry: false,
            recommendations: fatal_recommendations(error)
          }
        end
      end

      def build_benign_response(reason, tool_name: nil)
        {
          severity: SEVERITY_BENIGN,
          message: benign_message(reason),
          tool: tool_name,
          results: []
        }
      end

      def retryable?(error)
        RETRYABLE_ERROR_CLASSES.any? { |klass| error.is_a?(klass) } ||
          RETRYABLE_ERROR_NAMES.any? { |name| error.class.ancestors.any? { |a| a.name == name } }
      end

      def fatal?(error)
        FATAL_ERROR_CLASSES.any? { |klass| error.is_a?(klass) }
      end

      def database_error?(error)
        error.class.ancestors.any? { |a| a.name == "Sequel::DatabaseError" }
      end

      def retryable_message(error)
        case error
        when Errno::EACCES
          "Database file is temporarily inaccessible. Another process may hold the lock."
        when Errno::EAGAIN
          "Resource temporarily unavailable. Try again shortly."
        when IOError
          "I/O error during database access. Connection may have been interrupted."
        else
          if error.class.name&.include?("Busy")
            "Database is busy. Another operation is in progress."
          else
            "Temporary database error: #{error.message}"
          end
        end
      end

      def fatal_message(error)
        case error
        when Errno::ENOSPC
          "No disk space available for database operations."
        when Errno::EROFS
          "Database is on a read-only filesystem."
        when TypeError, NoMethodError
          "Internal error in memory system."
        when ArgumentError
          "Invalid parameters provided."
        else
          "Database error: #{error.message}"
        end
      end

      def fatal_recommendations(error)
        recs = ["Run memory.check_setup to diagnose the issue"]

        case error
        when Errno::ENOSPC
          recs << "Free up disk space and retry"
        when Errno::EROFS
          recs << "Check filesystem permissions"
        else
          if error.message.include?("corrupt") || error.message.include?("malformed")
            recs << "Database may be corrupted — run: claude-memory doctor"
            recs << "If unrecoverable: claude-memory init --force"
          else
            recs << "If persistent: claude-memory doctor"
          end
        end

        recs
      end

      def benign_message(reason)
        case reason
        when :no_results
          "No matching facts found. The memory system is working but has no relevant data for this query."
        when :not_initialized
          "Memory system not yet initialized. Facts will be stored as conversations happen."
        when :empty_database
          "Database exists but contains no facts yet. Use store_extraction to add facts."
        else
          "No data available."
        end
      end
    end
  end
end
