# Extraction Schema v1

This document defines the schema for extracted knowledge from transcripts.

## Extraction Object

```json
{
  "entities": [...],
  "facts": [...],
  "decisions": [...],
  "signals": [...]
}
```

## Entity

```json
{
  "type": "string",       // e.g., "database", "framework", "language", "platform", "repo", "module", "person", "service"
  "name": "string",       // canonical name
  "aliases": ["string"],  // optional: alternative names
  "confidence": 0.0-1.0   // optional: extraction confidence
}
```

## Fact

```json
{
  "subject": "string",           // entity name or "repo" for project-level
  "predicate": "string",         // e.g., "uses_database", "convention", "auth_method"
  "object": "string",            // entity name or literal value
  "polarity": "positive|negative", // default: "positive"
  "confidence": 0.0-1.0,         // extraction confidence
  "quote": "string",             // source text excerpt
  "strength": "stated|inferred", // how strongly evidenced
  "time_hint": "string",         // optional: ISO timestamp hint
  "decision_ref": "integer"      // optional: index into decisions array
}
```

## Decision

```json
{
  "title": "string",              // short summary (max 100 chars)
  "summary": "string",            // full description
  "status_hint": "string",        // "accepted", "proposed", "rejected"
  "emits_fact_indexes": [0, 1]    // optional: indices of facts this decision creates
}
```

## Signal

```json
{
  "kind": "string",   // "supersession", "conflict", "time_boundary"
  "value": "any"      // signal-specific value
}
```

### Signal Kinds

- **supersession**: `{kind: "supersession", value: true}` - indicates old knowledge may be replaced
- **conflict**: `{kind: "conflict", value: true}` - indicates contradictory information detected
- **time_boundary**: `{kind: "time_boundary", value: "2024-01-15"}` - temporal boundary marker

## Predicate Types

Canonical vocabulary defined in `lib/claude_memory/resolve/predicate_policy.rb`.

| Predicate | Cardinality | Exclusive |
|-----------|-------------|-----------|
| convention | multi | no |
| decision | multi | no |
| architecture | multi | no |
| uses_framework | multi | no |
| uses_language | multi | no |
| uses_database | single | yes |
| deployment_platform | single | yes |
| auth_method | single | yes |
