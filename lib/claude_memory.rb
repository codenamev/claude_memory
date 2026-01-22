# frozen_string_literal: true

module ClaudeMemory
  class Error < StandardError; end
end

require_relative "claude_memory/core/result"
require_relative "claude_memory/core/session_id"
require_relative "claude_memory/core/transcript_path"
require_relative "claude_memory/core/fact_id"
require_relative "claude_memory/core/null_fact"
require_relative "claude_memory/core/null_explanation"
require_relative "claude_memory/core/token_estimator"
require_relative "claude_memory/commands/base_command"
require_relative "claude_memory/commands/help_command"
require_relative "claude_memory/commands/version_command"
require_relative "claude_memory/commands/doctor_command"
require_relative "claude_memory/commands/promote_command"
require_relative "claude_memory/commands/search_command"
require_relative "claude_memory/commands/explain_command"
require_relative "claude_memory/commands/conflicts_command"
require_relative "claude_memory/commands/changes_command"
require_relative "claude_memory/commands/recall_command"
require_relative "claude_memory/commands/sweep_command"
require_relative "claude_memory/commands/ingest_command"
require_relative "claude_memory/commands/publish_command"
require_relative "claude_memory/commands/db_init_command"
require_relative "claude_memory/commands/init_command"
require_relative "claude_memory/commands/serve_mcp_command"
require_relative "claude_memory/commands/hook_command"
require_relative "claude_memory/commands/registry"
require_relative "claude_memory/cli"
require_relative "claude_memory/configuration"
require_relative "claude_memory/distill/distiller"
require_relative "claude_memory/distill/extraction"
require_relative "claude_memory/distill/null_distiller"
require_relative "claude_memory/domain/fact"
require_relative "claude_memory/domain/entity"
require_relative "claude_memory/domain/provenance"
require_relative "claude_memory/domain/conflict"
require_relative "claude_memory/hook/handler"
require_relative "claude_memory/index/query_options"
require_relative "claude_memory/index/index_query_logic"
require_relative "claude_memory/index/index_query"
require_relative "claude_memory/index/lexical_fts"
require_relative "claude_memory/ingest/privacy_tag"
require_relative "claude_memory/ingest/content_sanitizer"
require_relative "claude_memory/ingest/ingester"
require_relative "claude_memory/ingest/transcript_reader"
require_relative "claude_memory/infrastructure/file_system"
require_relative "claude_memory/infrastructure/in_memory_file_system"
require_relative "claude_memory/mcp/server"
require_relative "claude_memory/mcp/tools"
require_relative "claude_memory/publish"
require_relative "claude_memory/recall"
require_relative "claude_memory/shortcuts"
require_relative "claude_memory/resolve/predicate_policy"
require_relative "claude_memory/resolve/resolver"
require_relative "claude_memory/store/sqlite_store"
require_relative "claude_memory/store/store_manager"
require_relative "claude_memory/sweep/sweeper"
require_relative "claude_memory/version"

module ClaudeMemory
  def self.global_db_path(env = ENV)
    home = env["HOME"] || File.expand_path("~")
    File.join(home, ".claude", "memory.sqlite3")
  end

  def self.project_db_path(project_path = Dir.pwd)
    File.join(project_path, ".claude", "memory.sqlite3")
  end
end
