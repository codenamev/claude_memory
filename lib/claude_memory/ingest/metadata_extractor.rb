# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Ingest
    # Extracts session metadata from JSONL transcript messages
    # Captures git branch, working directory, Claude version, thinking level
    class MetadataExtractor
      # Extract metadata from raw transcript text
      # @param raw_text [String] the raw JSONL transcript content
      # @return [Hash] metadata hash with extracted values
      def extract(raw_text)
        return {} if raw_text.nil? || raw_text.empty?

        # Parse first JSONL message for metadata
        first_line = raw_text.lines.first
        return {} unless first_line&.strip&.start_with?("{")

        message = JSON.parse(first_line)
        {
          git_branch: extract_git_branch(message),
          cwd: extract_cwd(message),
          claude_version: extract_claude_version(message),
          thinking_level: extract_thinking_level(message)
        }.compact
      rescue JSON::ParserError
        {}
      end

      private

      def extract_git_branch(message)
        # Check for gitBranch in top-level or nested metadata
        message["gitBranch"] || message.dig("metadata", "gitBranch")
      end

      def extract_cwd(message)
        # Check for cwd or workingDirectory
        message["cwd"] || message["workingDirectory"] ||
          message.dig("metadata", "cwd") || message.dig("metadata", "workingDirectory")
      end

      def extract_claude_version(message)
        # Check various version fields
        message["version"] || message["claude_version"] ||
          message.dig("metadata", "version") || message.dig("metadata", "claude_version")
      end

      def extract_thinking_level(message)
        # Extract thinking metadata level
        message.dig("thinkingMetadata", "level") ||
          message.dig("metadata", "thinkingLevel")
      end
    end
  end
end
