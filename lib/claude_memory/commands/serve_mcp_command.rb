# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Starts MCP server
    class ServeMcpCommand < BaseCommand
      def call(_args)
        # Capture real stdout for MCP JSON-RPC transport, then redirect
        # $stdout to $stderr so accidental puts/print calls from gems or
        # debug output don't corrupt the stdio protocol stream.
        original_stdout = $stdout
        mcp_output = $stdout.dup
        $stdout = $stderr

        manager = ClaudeMemory::Store::StoreManager.new
        server = ClaudeMemory::MCP::Server.new(manager, output: mcp_output)
        server.run
        manager.close
        0
      ensure
        $stdout = original_stdout if original_stdout
      end
    end
  end
end
