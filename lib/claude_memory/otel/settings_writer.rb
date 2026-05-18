# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../core/result"

module ClaudeMemory
  module OTel
    # Idempotent reader/writer for the OTel-related env block in
    # .claude/settings.json. Each method returns Core::Result so the CLI
    # can render uniform success/failure output.
    #
    # Settings file shape (Claude Code reads this on session start):
    #
    #   {
    #     "env": {
    #       "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    #       "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    #       "OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:3377",
    #       "OTEL_METRICS_EXPORTER": "otlp",
    #       "OTEL_LOGS_EXPORTER": "otlp"
    #     }
    #   }
    #
    # Traces and prompt-content opt-ins write additional keys; #disable!
    # clears every key this module owns and leaves the rest of the file
    # untouched.
    class SettingsWriter
      DEFAULT_PORT = 3377

      OWNED_KEYS = %w[
        CLAUDE_CODE_ENABLE_TELEMETRY
        OTEL_EXPORTER_OTLP_PROTOCOL
        OTEL_EXPORTER_OTLP_ENDPOINT
        OTEL_METRICS_EXPORTER
        OTEL_LOGS_EXPORTER
        OTEL_TRACES_EXPORTER
        OTEL_LOG_USER_PROMPTS
      ].freeze

      def initialize(claude_dir, port: DEFAULT_PORT)
        @claude_dir = claude_dir
        @settings_path = File.join(@claude_dir, "settings.json")
        @port = port
      end

      attr_reader :settings_path

      def enable!
        update_env do |env|
          env["CLAUDE_CODE_ENABLE_TELEMETRY"] = "1"
          env["OTEL_EXPORTER_OTLP_PROTOCOL"] = "http/json"
          env["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://127.0.0.1:#{@port}"
          env["OTEL_METRICS_EXPORTER"] = "otlp"
          env["OTEL_LOGS_EXPORTER"] = "otlp"
        end
      end

      def disable!
        update_env do |env|
          OWNED_KEYS.each { |key| env.delete(key) }
        end
      end

      def enable_traces!
        update_env do |env|
          env["OTEL_TRACES_EXPORTER"] = "otlp"
        end
      end

      def disable_traces!
        update_env do |env|
          env["OTEL_TRACES_EXPORTER"] = "none"
        end
      end

      def capture_prompts!
        update_env do |env|
          env["OTEL_LOG_USER_PROMPTS"] = "1"
        end
      end

      def disable_capture_prompts!
        update_env do |env|
          env.delete("OTEL_LOG_USER_PROMPTS")
        end
      end

      # Read-only accessor — returns the current OTel-related env values
      # so the CLI's --status subcommand and the dashboard header can
      # render what's configured without re-implementing JSON parsing.
      def current_env
        load_settings.fetch("env", {}).slice(*OWNED_KEYS)
      end

      private

      def update_env
        FileUtils.mkdir_p(@claude_dir)
        settings = load_settings
        settings["env"] ||= {}
        yield settings["env"]
        write_settings(settings)
        Core::Result.success(settings["env"].slice(*OWNED_KEYS))
      rescue Errno::EACCES, Errno::ENOSPC, JSON::ParserError => e
        Core::Result.failure("settings.json write failed: #{e.message}")
      end

      def load_settings
        return {} unless File.exist?(@settings_path)
        raw = File.read(@settings_path)
        return {} if raw.strip.empty?
        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : {}
      end

      def write_settings(settings)
        File.write(@settings_path, JSON.pretty_generate(settings) + "\n")
      end
    end
  end
end
