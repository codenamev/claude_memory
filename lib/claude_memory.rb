# frozen_string_literal: true

module ClaudeMemory
  class Error < StandardError; end

  # Context marker to prevent self-ingestion of ClaudeMemory's own
  # meta-conversations (distiller subagents, sweeper sessions, etc.).
  # Include this marker in subagent prompts to exclude their transcripts
  # from being ingested into the knowledge base.
  SELF_CONTEXT_MARKER = "claude-memory-self"
end

require_relative "claude_memory/core/result"
require_relative "claude_memory/core/session_id"
require_relative "claude_memory/core/transcript_path"
require_relative "claude_memory/core/fact_id"
require_relative "claude_memory/core/null_fact"
require_relative "claude_memory/core/null_explanation"
require_relative "claude_memory/core/token_estimator"
require_relative "claude_memory/core/batch_loader"
require_relative "claude_memory/core/fact_ranker"
require_relative "claude_memory/core/rr_fusion"
require_relative "claude_memory/core/concept_ranker"
require_relative "claude_memory/core/scope_filter"
require_relative "claude_memory/core/result_builder"
require_relative "claude_memory/core/fact_collector"
require_relative "claude_memory/core/embedding_candidate_builder"
require_relative "claude_memory/core/fact_query_builder"
require_relative "claude_memory/core/result_sorter"
require_relative "claude_memory/core/relative_time"
require_relative "claude_memory/core/text_builder"
require_relative "claude_memory/core/snippet_extractor"
require_relative "claude_memory/core/fact_graph"
require_relative "claude_memory/commands/base_command"
require_relative "claude_memory/commands/checks/database_check"
require_relative "claude_memory/commands/checks/snapshot_check"
require_relative "claude_memory/commands/checks/claude_md_check"
require_relative "claude_memory/commands/checks/hooks_check"
require_relative "claude_memory/commands/checks/reporter"
require_relative "claude_memory/commands/checks/vec_check"
require_relative "claude_memory/commands/checks/distill_check"
require_relative "claude_memory/commands/help_command"
require_relative "claude_memory/commands/version_command"
require_relative "claude_memory/commands/doctor_command"
require_relative "claude_memory/commands/stats_command"
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
require_relative "claude_memory/commands/initializers/hooks_configurator"
require_relative "claude_memory/commands/initializers/mcp_configurator"
require_relative "claude_memory/commands/initializers/memory_instructions_writer"
require_relative "claude_memory/commands/initializers/database_ensurer"
require_relative "claude_memory/commands/initializers/project_initializer"
require_relative "claude_memory/commands/initializers/global_initializer"
require_relative "claude_memory/commands/init_command"
require_relative "claude_memory/commands/uninstall_command"
require_relative "claude_memory/commands/serve_mcp_command"
require_relative "claude_memory/commands/hook_command"
require_relative "claude_memory/commands/index_command"
require_relative "claude_memory/commands/recover_command"
require_relative "claude_memory/commands/compact_command"
require_relative "claude_memory/commands/export_command"
require_relative "claude_memory/commands/git_lfs_command"
require_relative "claude_memory/commands/install_skill_command"
require_relative "claude_memory/commands/completion_command"
require_relative "claude_memory/commands/embeddings_command"
require_relative "claude_memory/commands/reject_command"
require_relative "claude_memory/commands/restore_command"
require_relative "claude_memory/commands/census_command"
require_relative "claude_memory/commands/dashboard_command"
require_relative "claude_memory/dashboard/fact_presenter"
require_relative "claude_memory/dashboard/conflicts"
require_relative "claude_memory/dashboard/efficacy"
require_relative "claude_memory/dashboard/api"
require_relative "claude_memory/dashboard/server"
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
require_relative "claude_memory/embeddings/model_registry"
require_relative "claude_memory/embeddings/inspector"
require_relative "claude_memory/embeddings/generator"
require_relative "claude_memory/embeddings/fastembed_adapter"
require_relative "claude_memory/embeddings/api_adapter"
require_relative "claude_memory/embeddings/dimension_check"
require_relative "claude_memory/embeddings/resolver"
require_relative "claude_memory/embeddings/similarity"
require_relative "claude_memory/hook/context_injector"
require_relative "claude_memory/hook/distillation_runner"
require_relative "claude_memory/hook/exit_codes"
require_relative "claude_memory/hook/handler"
require_relative "claude_memory/hook/error_classifier"
require_relative "claude_memory/index/query_options"
require_relative "claude_memory/index/index_query_logic"
require_relative "claude_memory/index/index_query"
require_relative "claude_memory/index/lexical_fts"
require_relative "claude_memory/index/vector_index"
require_relative "claude_memory/ingest/privacy_tag"
require_relative "claude_memory/ingest/content_sanitizer"
require_relative "claude_memory/ingest/metadata_extractor"
require_relative "claude_memory/ingest/observation_compressor"
require_relative "claude_memory/ingest/tool_extractor"
require_relative "claude_memory/ingest/tool_filter"
require_relative "claude_memory/ingest/ingester"
require_relative "claude_memory/ingest/transcript_reader"
require_relative "claude_memory/activity_log"
require_relative "claude_memory/logging/logger"
require_relative "claude_memory/infrastructure/file_system"
require_relative "claude_memory/infrastructure/in_memory_file_system"
require_relative "claude_memory/infrastructure/operation_tracker"
require_relative "claude_memory/infrastructure/schema_validator"
require_relative "claude_memory/mcp/instructions_builder"
require_relative "claude_memory/mcp/query_guide"
require_relative "claude_memory/mcp/text_summary"
require_relative "claude_memory/mcp/tool_helpers"
require_relative "claude_memory/mcp/server"
require_relative "claude_memory/mcp/tools"
require_relative "claude_memory/publish"
require_relative "claude_memory/recall/dual_query_template"
require_relative "claude_memory/recall/expansion_detector"
require_relative "claude_memory/recall/query_core"
require_relative "claude_memory/recall/legacy_engine"
require_relative "claude_memory/recall/dual_engine"
require_relative "claude_memory/recall"
require_relative "claude_memory/shortcuts"
require_relative "claude_memory/resolve/predicate_policy"
require_relative "claude_memory/resolve/resolver"
require_relative "claude_memory/store/sqlite_store"
require_relative "claude_memory/store/store_manager"
require_relative "claude_memory/sweep/maintenance"
require_relative "claude_memory/sweep/sweeper"
require_relative "claude_memory/version"

module ClaudeMemory
  def self.global_db_path(env = ENV)
    Configuration.new(env).global_db_path
  end

  def self.project_db_path(project_path = Dir.pwd)
    Configuration.new.project_db_path(project_path)
  end

  # Module-level logger instance, shared across components
  # @return [Logging::Logger, Logging::NullLogger]
  def self.logger
    @logger ||= Logging::Logger.new
  end

  # Replace the module-level logger (useful for testing)
  # @param logger [Logging::Logger, Logging::NullLogger]
  def self.logger=(logger)
    @logger = logger
  end
end
