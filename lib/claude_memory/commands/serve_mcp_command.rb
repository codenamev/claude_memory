# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Starts MCP server
    class ServeMcpCommand < BaseCommand
      def call(_args)
        manager = ClaudeMemory::Store::StoreManager.new
        server = ClaudeMemory::MCP::Server.new(manager)
        server.run
        manager.close
        0
      end
    end
  end
end
