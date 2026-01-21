# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Displays version information for claude-memory
    class VersionCommand < BaseCommand
      def call(_args)
        stdout.puts "claude-memory #{ClaudeMemory::VERSION}"
        0
      end
    end
  end
end
