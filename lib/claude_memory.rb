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
require_relative "claude_memory/index/lexical_fts"
require_relative "claude_memory/distill/extraction"
require_relative "claude_memory/distill/distiller"
require_relative "claude_memory/distill/null_distiller"
require_relative "claude_memory/resolve/predicate_policy"
require_relative "claude_memory/resolve/resolver"
require_relative "claude_memory/recall"
