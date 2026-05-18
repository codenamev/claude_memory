# frozen_string_literal: true

module ClaudeMemory
  module OTel
    # Canonical metric value types stored in otel_metrics.value_type.
    module ValueType
      INT = "int"
      DOUBLE = "double"
    end

    # Canonical event names emitted by Claude Code's OTel instrumentation.
    # Used by panels for filtering and by the parser when stripping the
    # `claude_code.` prefix off `event.name` attributes.
    module EventName
      USER_PROMPT = "user_prompt"
      TOOL_RESULT = "tool_result"
      API_REQUEST = "api_request"
      API_ERROR = "api_error"
      API_REQUEST_BODY = "api_request_body"
      API_RESPONSE_BODY = "api_response_body"

      API_PAIR = [API_REQUEST, API_ERROR].freeze
      PROMPT_BODY_FAMILY = [USER_PROMPT, TOOL_RESULT, API_REQUEST_BODY, API_RESPONSE_BODY].freeze
    end

    # Canonical metric names that the dashboard queries.
    module MetricName
      TOKEN_USAGE = "claude_code.token.usage"
      COST_USAGE = "claude_code.cost.usage"
    end
  end
end
