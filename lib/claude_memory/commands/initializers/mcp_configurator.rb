# frozen_string_literal: true

require "fileutils"
require "json"

module ClaudeMemory
  module Commands
    module Initializers
      # Configures MCP server for ClaudeMemory
      class McpConfigurator
        def initialize(stdout)
          @stdout = stdout
        end

        def configure_project_mcp
          mcp_path = ".claude.json"

          existing = load_json_file(mcp_path)
          existing["mcpServers"] ||= {}
          existing["mcpServers"]["claude-memory"] = {
            "type" => "stdio",
            "command" => "claude-memory",
            "args" => ["serve-mcp"]
          }

          File.write(mcp_path, JSON.pretty_generate(existing))
          @stdout.puts "✓ Configured MCP server in #{mcp_path}"
        end

        def configure_global_mcp
          mcp_path = File.join(Dir.home, ".claude.json")

          existing = load_json_file(mcp_path)
          existing["mcpServers"] ||= {}
          existing["mcpServers"]["claude-memory"] = {
            "type" => "stdio",
            "command" => "claude-memory",
            "args" => ["serve-mcp"]
          }

          File.write(mcp_path, JSON.pretty_generate(existing))
          @stdout.puts "✓ Configured MCP server in #{mcp_path}"
        end

        private

        def load_json_file(path)
          return {} unless File.exist?(path)
          JSON.parse(File.read(path))
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
