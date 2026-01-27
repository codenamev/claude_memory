# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Checks if CLAUDE.md exists and imports snapshot
      class ClaudeMdCheck
        CLAUDE_MD_PATH = ".claude/CLAUDE.md"

        def call
          unless File.exist?(CLAUDE_MD_PATH)
            return {
              status: :warning,
              label: "claude_md",
              message: "No .claude/CLAUDE.md found",
              details: {path: CLAUDE_MD_PATH}
            }
          end

          content = File.read(CLAUDE_MD_PATH)

          if content.include?("claude_memory.generated.md")
            {
              status: :ok,
              label: "claude_md",
              message: "CLAUDE.md imports snapshot",
              details: {path: CLAUDE_MD_PATH}
            }
          else
            {
              status: :warning,
              label: "claude_md",
              message: "CLAUDE.md does not import snapshot",
              details: {path: CLAUDE_MD_PATH}
            }
          end
        end
      end
    end
  end
end
