# frozen_string_literal: true

# Migration v13: Add mcp_tool_calls telemetry table
# Records every MCP server tool invocation for usage stats and ROI tracking.
# Distinct from `tool_calls` (v3), which stores Claude Code tool observations
# extracted from transcripts.
Sequel.migration do
  up do
    create_table?(:mcp_tool_calls) do
      primary_key :id
      String :tool_name, null: false
      String :called_at, null: false
      Integer :duration_ms, null: false
      Integer :result_count
      String :scope
      String :error_class
    end

    run "CREATE INDEX IF NOT EXISTS idx_mcp_tool_calls_name_time ON mcp_tool_calls(tool_name, called_at)"
    run "CREATE INDEX IF NOT EXISTS idx_mcp_tool_calls_called_at ON mcp_tool_calls(called_at)"
  end

  down do
    drop_table?(:mcp_tool_calls)
  end
end
