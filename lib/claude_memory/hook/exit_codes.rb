# frozen_string_literal: true

module ClaudeMemory
  module Hook
    module ExitCodes
      # Success or graceful shutdown
      SUCCESS = 0

      # Non-blocking error (shown to user, session continues)
      # Example: Missing transcript file, database not initialized
      WARNING = 1

      # Blocking error (fed to Claude for processing)
      # Example: Database corruption, schema mismatch
      ERROR = 2
    end
  end
end
