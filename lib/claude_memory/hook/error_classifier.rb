# frozen_string_literal: true

module ClaudeMemory
  module Hook
    # Classifies hook errors into transport/infrastructure failures
    # vs client/programming bugs to determine exit code behavior.
    #
    # Transport errors (exit 0): Infrastructure failures that shouldn't
    # block Claude Code sessions. Memory is optional — degrade gracefully.
    #
    # Client errors (exit 2): Programming bugs or invalid input that
    # developers should see and fix.
    #
    # Source: claude-mem hook-command.ts:26-66
    module ErrorClassifier
      # Infrastructure/transport error class names — resolved lazily
      # to avoid load-order dependency on Sequel
      TRANSPORT_ERROR_NAMES = %w[
        Sequel::DatabaseConnectionError
        Sequel::DatabaseError
      ].freeze

      TRANSPORT_ERROR_CLASSES = [
        Errno::EACCES,
        Errno::ENOSPC,
        Errno::EISDIR,
        Errno::EROFS,
        IOError
      ].freeze

      # Client/programming error classes — surface to developer
      CLIENT_ERROR_CLASSES = [
        Handler::PayloadError,
        JSON::ParserError,
        TypeError,
        NoMethodError,
        ArgumentError
      ].freeze

      module_function

      # Returns true for infrastructure failures that should not block sessions
      def transport_error?(error)
        TRANSPORT_ERROR_CLASSES.any? { |klass| error.is_a?(klass) } ||
          TRANSPORT_ERROR_NAMES.any? { |name| error.class.ancestors.any? { |a| a.name == name } }
      end

      # Returns true for programming bugs that developers should fix
      def client_error?(error)
        CLIENT_ERROR_CLASSES.any? { |klass| error.is_a?(klass) }
      end

      # Returns the appropriate exit code for an error
      def exit_code_for(error)
        if transport_error?(error)
          ExitCodes::SUCCESS
        elsif client_error?(error)
          ExitCodes::ERROR
        else
          # Unknown errors default to graceful degradation —
          # memory should never block Claude Code sessions
          ExitCodes::SUCCESS
        end
      end
    end
  end
end
