# frozen_string_literal: true

require "json"
require_relative "instructions_builder"
require_relative "query_guide"
require_relative "text_summary"
require_relative "error_classifier"
require_relative "telemetry"

module ClaudeMemory
  module MCP
    # MCP JSON-RPC server over stdio.
    # Reads newline-delimited JSON requests from input, dispatches to Tools,
    # and writes JSON responses to output.
    class Server
      PROTOCOL_VERSION = "2024-11-05"

      # @param store_or_manager [Store::SQLiteStore, Store::StoreManager] database backend
      # @param input [IO] input stream for JSON-RPC requests (default: $stdin)
      # @param output [IO] output stream for JSON-RPC responses (default: $stdout)
      def initialize(store_or_manager, input: $stdin, output: $stdout)
        @store_or_manager = store_or_manager
        @tools = Tools.new(store_or_manager)
        @telemetry = Telemetry.new(store_or_manager)
        @input = input
        @output = output
        @running = false
      end

      # Start the read loop, blocking until input is exhausted or stop is called.
      # @return [void]
      def run
        @running = true
        while @running
          line = @input.gets
          break unless line

          handle_message(line.strip)
        end
      end

      # Signal the read loop to exit after the current message.
      # @return [void]
      def stop
        @running = false
      end

      private

      # @return [void]
      def handle_message(line)
        return if line.empty?

        request = nil
        begin
          request = JSON.parse(line)
          response = process_request(request)
          send_response(response) if response
        rescue JSON::ParserError => e
          send_error(-32700, "Parse error: #{e.message}", 0)
        rescue => e
          # Per JSON-RPC 2.0: never respond to notifications, even on error
          request_id = request&.fetch("id", nil)
          send_error(-32603, "Internal error: #{e.message}", request_id) unless request_id.nil?
        end
      end

      # @return [Hash, nil] JSON-RPC response hash, or nil for notifications
      def process_request(request)
        id = request["id"]
        method = request["method"]

        # Per JSON-RPC 2.0: a request without an id is a notification and
        # MUST NOT receive a response. MCP relies on this for
        # `notifications/initialized` after the initialize handshake.
        return nil if id.nil?

        case method
        when "initialize"
          handle_initialize(id, request["params"])
        when "tools/list"
          handle_tools_list(id)
        when "tools/call"
          handle_tools_call(id, request["params"])
        when "prompts/list"
          handle_prompts_list(id)
        when "prompts/get"
          handle_prompts_get(id, request["params"])
        when "shutdown"
          @running = false
          {jsonrpc: "2.0", id: id, result: nil}
        else
          {jsonrpc: "2.0", id: id, error: {code: -32601, message: "Method not found: #{method}"}}
        end
      end

      # @return [Hash] initialize response with capabilities and server info
      def handle_initialize(id, _params)
        {
          jsonrpc: "2.0",
          id: id,
          result: {
            protocolVersion: PROTOCOL_VERSION,
            capabilities: {
              tools: {},
              prompts: {}
            },
            serverInfo: {
              name: "claude-memory",
              version: ClaudeMemory::VERSION
            },
            instructions: InstructionsBuilder.build(@store_or_manager)
          }
        }
      end

      # @return [Hash] list of available tool definitions
      def handle_tools_list(id)
        {
          jsonrpc: "2.0",
          id: id,
          result: {
            tools: @tools.definitions
          }
        }
      end

      # @return [Hash] tool result with dual content/structuredContent
      def handle_tools_call(id, params)
        name = params["name"]
        arguments = params["arguments"] || {}

        result = @telemetry.record(name, arguments) do
          @tools.call(name, arguments)
        end

        # Release database connections after each tool call
        # This prevents lock contention with hook commands
        # Connections are automatically reopened on next use
        release_connections

        text_summary = TextSummary.for_tool(name, result)

        {
          jsonrpc: "2.0",
          id: id,
          result: {
            content: [
              {type: "text", text: text_summary}
            ],
            structuredContent: result
          }
        }
      end

      # @return [Hash] list of available prompt definitions
      def handle_prompts_list(id)
        {
          jsonrpc: "2.0",
          id: id,
          result: {
            prompts: [QueryGuide.definition]
          }
        }
      end

      # @return [Hash] prompt content or error if unknown
      def handle_prompts_get(id, params)
        name = params&.dig("name")

        if name == QueryGuide::PROMPT_NAME
          {jsonrpc: "2.0", id: id, result: QueryGuide.content}
        else
          {jsonrpc: "2.0", id: id, error: {code: -32602, message: "Unknown prompt: #{name}"}}
        end
      end

      def release_connections
        if @store_or_manager.is_a?(Store::StoreManager)
          # Release both global and project store connections
          @store_or_manager.global_store&.db&.disconnect
          @store_or_manager.project_store&.db&.disconnect
        elsif @store_or_manager.respond_to?(:db)
          # Release single store connection (legacy)
          @store_or_manager.db.disconnect
        end
      rescue Sequel::DatabaseError, Extralite::Error
        # Silently ignore disconnect errors
        # Connection will be reopened automatically on next use
      end

      def send_response(response)
        @output.puts(JSON.generate(response))
        @output.flush
      end

      def send_error(code, message, id)
        send_response({
          jsonrpc: "2.0",
          id: id,
          error: {code: code, message: message}
        })
      end
    end
  end
end
