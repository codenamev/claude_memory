#!/usr/bin/env bash
# Wrapper script for claude-memory MCP server.
# Used by the Claude Code plugin to launch the MCP server.
# Falls back to a JSON-RPC error if the gem is not installed.

set -euo pipefail

if command -v claude-memory > /dev/null 2>&1; then
  exec claude-memory serve-mcp
else
  # Return a JSON-RPC error so Claude Code surfaces it to the user
  echo '{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"claude-memory gem not found. Install with: gem install claude_memory"}}'
  exit 1
fi
