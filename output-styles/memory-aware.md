---
keep-coding-instructions: true
---

# Memory-Aware Output Style

This output style helps Claude format responses in a way that makes knowledge easy to capture and recall from memory.

## Stating Decisions and Conventions

When making or documenting decisions, use clear declarative language:

**Good examples:**
- "We decided to use PostgreSQL for the main database"
- "We agreed to use 4-space indentation for Ruby files"
- "Convention: All API responses include a `meta` object"
- "Standard: Test files go in `spec/` matching the source structure"

**Why this helps:** Clear statements are easier to extract and recall later.

## Signaling Changes and Supersession

When replacing or updating previous decisions, make the change explicit:

**Good examples:**
- "We're switching from Redis to Memcached for caching"
- "This supersedes our earlier decision to use REST APIs—we're now using GraphQL"
- "We no longer validate email format server-side; client-side only"

**Why this helps:** Memory can track supersession and resolve conflicts.

## Acknowledging Contradictions

When encountering conflicting information, call it out explicitly:

**Good examples:**
- "This contradicts our earlier decision to use MySQL"
- "I found conflicting information: the README says Postgres, but the config uses SQLite"
- "Two facts conflict: authentication was JWT, now seeing sessions"

**Why this helps:** Explicit contradictions help memory identify conflicts to resolve.

## Citing Sources

When referencing previous knowledge, distinguish memory from code exploration:

**Good examples:**
- "From memory: We use RSpec for testing (fact #42)"
- "According to earlier conversations: PostgreSQL is the primary database"
- "From code exploration: Found 3 additional test frameworks in Gemfile"

**Why this helps:** Clear attribution makes it easier to verify and explain facts.

## Response Format

Use structured language that makes facts extractable:

**Technology choices:**
- "This project uses [technology] for [purpose]"
- "We chose [X] over [Y] because [reason]"

**Architectural patterns:**
- "The architecture follows [pattern]"
- "Components communicate via [method]"

**Rules and constraints:**
- "Rule: [statement]"
- "Constraint: [limitation]"
- "Requirement: [need]"

**Why this helps:** Structured statements are easier to parse and store.
