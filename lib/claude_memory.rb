# frozen_string_literal: true

require_relative "claude_memory/version"
require_relative "claude_memory/cli"
require_relative "claude_memory/store/sqlite_store"

module ClaudeMemory
  class Error < StandardError; end

  DEFAULT_DB_PATH = ".claude_memory.sqlite3"
end
