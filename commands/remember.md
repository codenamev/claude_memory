---
description: Store something in memory
disable-model-invocation: true
argument-hint: [what to remember]
---

Store the following in memory using `memory.store_extraction`:

$ARGUMENTS

## Guidelines

1. Choose appropriate entity types:
   - `database`, `framework`, `language`, `platform`, `tool`, `convention`

2. Choose appropriate predicates:
   - `uses_database`, `uses_framework`, `uses_language`, `uses_tool`
   - `has_convention`, `prefers`, `decision`

3. Set scope:
   - Use `scope_hint: "global"` if the user says this applies to all projects
   - Use `scope_hint: "project"` (default) for project-specific facts

4. Include the user's statement as the `quote` for provenance.

5. Confirm what was stored.
