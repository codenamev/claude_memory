# Deprecated: /check-memory

This skill is **no longer needed** and should not be used.

## Why Deprecated?

The `/check-memory` skill was created to force a "check memory before file exploration" workflow. However, this should be **automatic**, not manual.

## What Replaced It?

The enhanced `memory-aware` output style now handles this automatically by:
- Explicitly instructing Claude to check memory FIRST before file reads
- Providing clear workflow: memory.recall → then file exploration if needed
- Making this behavior persistent across all conversations

## If You Need Debugging

Use `/debug-memory` instead to troubleshoot ClaudeMemory installation issues.

## Migration

If you were using `/check-memory`:
- **Remove** any references to it
- **Use** the `memory-aware` output style (automatically applied)
- **Trust** that Claude will check memory first automatically

## Archive Date

Deprecated: 2026-01-29
