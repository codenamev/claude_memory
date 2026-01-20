# frozen_string_literal: true

require "json"

module ClaudeMemory
  module MCP
    class Server
      PROTOCOL_VERSION = "2024-11-05"

      def initialize(store_or_manager, input: $stdin, output: $stdout)
        @store_or_manager = store_or_manager
        @tools = Tools.new(store_or_manager)
        @input = input
        @output = output
        @running = false
      end

      def run
        @running = true
        while @running
          line = @input.gets
          break unless line

          handle_message(line.strip)
        end
      end

      def stop
        @running = false
      end

      private

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
          request_id = request&.fetch("id", nil) || 0
          send_error(-32603, "Internal error: #{e.message}", request_id)
        end
      end

      def process_request(request)
        id = request["id"]
        method = request["method"]

        case method
        when "initialize"
          handle_initialize(id, request["params"])
        when "tools/list"
          handle_tools_list(id)
        when "tools/call"
          handle_tools_call(id, request["params"])
        when "shutdown"
          @running = false
          {jsonrpc: "2.0", id: id, result: nil}
        else
          {jsonrpc: "2.0", id: id, error: {code: -32601, message: "Method not found: #{method}"}}
        end
      end

      def handle_initialize(id, _params)
        {
          jsonrpc: "2.0",
          id: id,
          result: {
            protocolVersion: PROTOCOL_VERSION,
            capabilities: {
              tools: {}
            },
            serverInfo: {
              name: "claude-memory",
              version: ClaudeMemory::VERSION
            }
          }
        }
      end

      def handle_tools_list(id)
        {
          jsonrpc: "2.0",
          id: id,
          result: {
            tools: @tools.definitions
          }
        }
      end

      def handle_tools_call(id, params)
        name = params["name"]
        arguments = params["arguments"] || {}

        result = @tools.call(name, arguments)

        {
          jsonrpc: "2.0",
          id: id,
          result: {
            content: [
              {type: "text", text: JSON.generate(result)}
            ]
          }
        }
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
