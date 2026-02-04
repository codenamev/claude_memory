# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Logging
    # Structured JSON logger for ClaudeMemory operations.
    # Outputs machine-readable JSON log entries to a configurable stream.
    #
    # Log levels: DEBUG (0), INFO (1), WARN (2), ERROR (3)
    # Configure via CLAUDE_MEMORY_LOG_LEVEL env var (default: WARN)
    #
    # @example Basic usage
    #   logger = ClaudeMemory::Logging::Logger.new
    #   logger.info("ingest", message: "Ingested 1024 bytes", content_id: 42)
    #
    # @example With custom output
    #   logger = ClaudeMemory::Logging::Logger.new(output: StringIO.new, level: :debug)
    #   logger.debug("recall", message: "Query executed", query: "test", results: 5)
    class Logger
      DEBUG = 0
      INFO = 1
      WARN = 2
      ERROR = 3

      LEVELS = {debug: DEBUG, info: INFO, warn: WARN, error: ERROR}.freeze

      attr_reader :level

      # @param output [IO] output stream for log entries (default: $stderr)
      # @param level [Symbol, String] minimum log level (default: from env or :warn)
      def initialize(output: $stderr, level: nil)
        @output = output
        @level = resolve_level(level)
      end

      def debug(component, **fields)
        log(:debug, component, **fields)
      end

      def info(component, **fields)
        log(:info, component, **fields)
      end

      def warn(component, **fields)
        log(:warn, component, **fields)
      end

      def error(component, **fields)
        log(:error, component, **fields)
      end

      def debug?
        @level <= DEBUG
      end

      def info?
        @level <= INFO
      end

      private

      def log(level_sym, component, **fields)
        return unless LEVELS[level_sym] >= @level

        entry = {
          timestamp: Time.now.utc.iso8601(3),
          level: level_sym.to_s.upcase,
          component: component
        }.merge(fields)

        @output.puts(JSON.generate(entry))
      rescue IOError
        # Silently ignore write failures (e.g., closed pipe)
      end

      def resolve_level(explicit_level)
        if explicit_level
          sym = explicit_level.to_s.downcase.to_sym
          LEVELS.fetch(sym, WARN)
        else
          env_level = ENV["CLAUDE_MEMORY_LOG_LEVEL"]
          if env_level
            sym = env_level.downcase.to_sym
            LEVELS.fetch(sym, WARN)
          else
            WARN
          end
        end
      end
    end

    # Null logger that discards all output (for testing or silent operation)
    class NullLogger
      def debug(component, **fields) = nil

      def info(component, **fields) = nil

      def warn(component, **fields) = nil

      def error(component, **fields) = nil

      def debug? = false

      def info? = false

      def level
        Logger::ERROR + 1
      end
    end
  end
end
