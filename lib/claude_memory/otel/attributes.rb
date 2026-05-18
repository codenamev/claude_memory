# frozen_string_literal: true

require "json"

module ClaudeMemory
  module OTel
    # Value object wrapping an OTel attribute hash (already flattened from
    # the OTLP KeyValue representation by OtlpJsonEnvelope). Hides the
    # primitive Hash from callers so panels and ingestors don't reach into
    # raw JSON keys.
    #
    # All accessors return nil when the underlying attribute is missing.
    # Frozen on construction — pass a fresh hash if you need to mutate.
    class Attributes
      # OTel keys we treat as "captured prompt content". Used by
      # #contains_prompt_content? to flag privacy concerns regardless of
      # which content flag was flipped (OTEL_LOG_USER_PROMPTS,
      # OTEL_LOG_TOOL_CONTENT, OTEL_LOG_RAW_API_BODIES).
      PROMPT_CONTENT_KEYS = %w[
        prompt
        body
        tool_input
        tool.output
        full_command
        user_prompt
      ].freeze

      # @param hash [Hash] flattened attributes (string keys)
      def initialize(hash)
        @hash = (hash || {}).dup.freeze
        freeze
      end

      # Parse a JSON string into Attributes. Returns Attributes wrapping
      # an empty hash for nil, blank, or unparseable input — matches the
      # tolerance the existing dashboard panels expect.
      #
      # @param json_string [String, nil]
      # @return [Attributes]
      def self.from_json(json_string)
        return new({}) if json_string.nil? || json_string.empty?
        new(JSON.parse(json_string))
      rescue JSON::ParserError
        new({})
      end

      def to_h
        @hash
      end

      def to_json(*args)
        @hash.to_json(*args)
      end

      def [](key)
        @hash[key.to_s]
      end

      # Claude Code attaches `prompt.id` to events that should be UNION'd into
      # the prompt journey. See docs/claude_monitoring.md.
      def prompt_id
        @hash["prompt.id"] || @hash["prompt_id"]
      end

      def session_id
        @hash["session.id"] || @hash["session_id"]
      end

      # GenAI semconv canonical key + Claude Code's `model` alias.
      def model
        @hash["gen_ai.request.model"] || @hash["model"]
      end

      def tool_name
        @hash["tool_name"]
      end

      # Cost counter values arrive as the metric value, not as an attribute.
      # The `type` attribute on token.usage tells us input/output/cacheRead/
      # cacheCreation; this is only useful for token rows. Returns nil when
      # missing so callers can guard with #compact.
      def token_type
        @hash["type"]
      end

      # Token count carried on a token.usage data point.
      # @param row [Hash] otel_metrics row
      def self.token_count(row)
        (row[:value_int] || row[:value_float] || 0).to_i
      end

      # Tool execution duration in ms when the event is a tool_result.
      # @return [Integer, nil]
      def duration_ms
        value = @hash["duration_ms"]
        value&.to_i
      end

      def query_source
        @hash["query_source"]
      end

      def speed
        @hash["speed"]
      end

      # True when any attribute carries actual prompt or body content. Used
      # by panels to render a one-line privacy notice without auto-flipping
      # OTEL_LOG_USER_PROMPTS.
      def contains_prompt_content?
        PROMPT_CONTENT_KEYS.any? do |key|
          value = @hash[key]
          !value.nil? && !value.to_s.strip.empty?
        end
      end
    end
  end
end
