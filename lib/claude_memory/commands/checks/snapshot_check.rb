# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Checks if published snapshot exists
      class SnapshotCheck
        SNAPSHOT_PATH = ".claude/rules/claude_memory.generated.md"

        def call
          if File.exist?(SNAPSHOT_PATH)
            {
              status: :ok,
              label: "snapshot",
              message: "Published snapshot exists",
              details: {path: SNAPSHOT_PATH}
            }
          else
            {
              status: :warning,
              label: "snapshot",
              message: "No published snapshot found. Run 'claude-memory publish'",
              details: {path: SNAPSHOT_PATH}
            }
          end
        end
      end
    end
  end
end
