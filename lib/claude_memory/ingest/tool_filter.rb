# frozen_string_literal: true

module ClaudeMemory
  module Ingest
    # Filters tool calls during ingestion to reduce noise
    # Follows Functional Core pattern - no I/O, just predicate logic
    #
    # Supports two modes:
    #   - skip_tools (blacklist): Skip listed tools, capture everything else
    #   - capture_tools (whitelist): Only capture listed tools, skip everything else
    #
    # When both are empty, all tools are captured (no filtering).
    class ToolFilter
      # Default tools to skip - high-volume, read-only tools that add noise
      DEFAULT_SKIP_TOOLS = %w[Read Glob Grep].freeze

      attr_reader :skip_tools, :capture_tools

      # @param skip_tools [Array<String>] Tool names to skip (blacklist mode)
      # @param capture_tools [Array<String>] Tool names to capture exclusively (whitelist mode)
      def initialize(skip_tools: nil, capture_tools: nil)
        @skip_tools = skip_tools || DEFAULT_SKIP_TOOLS
        @capture_tools = capture_tools
      end

      # Check if a tool call should be captured
      # @param tool_name [String] Name of the tool
      # @return [Boolean] true if the tool should be captured
      def capture?(tool_name)
        return false if tool_name.nil?

        # Whitelist mode takes precedence
        if @capture_tools && !@capture_tools.empty?
          return @capture_tools.include?(tool_name)
        end

        # Blacklist mode
        !@skip_tools.include?(tool_name)
      end

      # Filter an array of tool call hashes
      # @param tool_calls [Array<Hash>] Tool calls with :tool_name key
      # @return [Array<Hash>] Filtered tool calls
      def filter(tool_calls)
        tool_calls.select { |tc| capture?(tc[:tool_name]) }
      end

      # Create a filter with no filtering (captures all tools)
      # @return [ToolFilter] Permissive filter
      def self.allow_all
        new(skip_tools: [], capture_tools: nil)
      end
    end
  end
end
