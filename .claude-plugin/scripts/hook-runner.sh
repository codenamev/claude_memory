#!/usr/bin/env bash
# Generic hook delegate for claude-memory.
# Used by the Claude Code plugin to run hook subcommands.
# Usage: hook-runner.sh <subcommand> [args...]
# Exit 0 on missing binary to avoid blocking Claude Code.

set -uo pipefail

if command -v claude-memory > /dev/null 2>&1; then
  exec claude-memory hook "$@"
else
  echo "claude-memory gem not found. Install with: gem install claude_memory" >&2
  exit 0
fi
