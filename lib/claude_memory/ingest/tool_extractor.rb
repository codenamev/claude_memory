# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Ingest
    # Extracts tool usage information from JSONL transcript messages
    # Tracks which tools were called during a session
    class ToolExtractor
      # Extract tool calls from raw transcript text
      # @param raw_text [String] the raw JSONL transcript content
      # @return [Array<Hash>] array of tool call hashes
      def extract(raw_text)
        return [] if raw_text.nil? || raw_text.empty?

        tools = []

        raw_text.lines.each do |line|
          next unless line.strip.start_with?("{")

          message = parse_message(line)
          next unless message

          extract_tools_from_message(message, tools)
        end

        tools
      rescue
        # If we encounter any parsing errors, return what we've collected so far
        tools
      end

      private

      def parse_message(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def extract_tools_from_message(message, tools)
        # Look for assistant messages with content blocks
        return unless message["type"] == "assistant"

        content = message.dig("message", "content")
        return unless content.is_a?(Array)

        timestamp = message["timestamp"] || Time.now.utc.iso8601

        content.each do |block|
          next unless block["type"] == "tool_use"

          tools << {
            tool_name: block["name"],
            tool_input: serialize_tool_input(block["input"]),
            timestamp: timestamp,
            is_error: false
          }
        end
      end

      def serialize_tool_input(input)
        return nil unless input

        # Convert to JSON, truncating if too large
        json = input.to_json
        (json.length > 1000) ? json[0...1000] + "..." : json
      end
    end
  end
end
