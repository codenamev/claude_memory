# frozen_string_literal: true

module ClaudeMemory
  class Error < StandardError; end

  DEFAULT_DB_PATH = ".claude_memory.sqlite3"
end

require_relative "claude_memory/version"
require_relative "claude_memory/cli"
require_relative "claude_memory/store/sqlite_store"
require_relative "claude_memory/ingest/transcript_reader"
require_relative "claude_memory/ingest/ingester"
