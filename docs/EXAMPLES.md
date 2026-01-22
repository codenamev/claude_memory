# ClaudeMemory Examples

Real-world use cases and example conversations showing how ClaudeMemory works in practice.

## Example 1: New Project Setup

**Scenario:** Starting a new Rails project

### The Conversation

```
You: "I'm starting a new Rails 7 project with PostgreSQL and deploying to Heroku"

Claude: "Great! Let me help you set up your Rails 7 project. I'll create the initial
        structure with PostgreSQL configuration..."

[Claude helps with setup tasks]
```

### Behind the Scenes

On session stop, ClaudeMemory automatically extracts and stores:
- **uses_framework**: Rails 7 (project scope)
- **uses_database**: PostgreSQL (project scope)
- **deployment_platform**: Heroku (project scope)

**No user action needed!**

### Later Session

```
You: "Help me add a new User model"

Claude: "Based on my memory, you're using Rails 7 with PostgreSQL. I'll create a
        migration for the users table..."
```

**What happened:**
- Claude called `memory.recall` automatically
- Retrieved project facts about Rails and PostgreSQL
- Applied context to the current task

---

## Example 2: Global Coding Preferences

**Scenario:** Establishing personal coding conventions

### The Conversation

```
You: "I always prefer 4-space indentation and descriptive variable names over
      abbreviations"

Claude: "I'll remember that preference globally and apply it to all your projects."
```

### Behind the Scenes

Stored with **scope: global**:
- **convention**: "4-space indentation" (global)
- **convention**: "descriptive variable names over abbreviations" (global)

### Later (Different Project)

```
You: "Write a function to calculate the total price with tax"

Claude: "Here's a function with 4-space indentation and descriptive variable names:

def calculate_total_price_with_tax(subtotal, tax_rate)
    tax_amount = subtotal * tax_rate
    total = subtotal + tax_amount
    total
end
"
```

**What happened:**
- Claude automatically recalled global conventions
- Applied 4-space indentation without being asked
- Used descriptive names (`subtotal`, `tax_rate`, `tax_amount`, `total`)

---

## Example 3: Architecture Decisions

**Scenario:** Recording and recalling design decisions

### Initial Decision

```
You: "We decided to use a microservices architecture for this app, with JWT
      authentication and REST APIs"

Claude: "Got it. I'll record that architectural decision for future reference."
```

### Behind the Scenes

Stored as decisions:
- **decision**: "Use microservices architecture" (project scope)
- **auth_method**: "JWT" (project scope)
- **decision**: "REST APIs for service communication" (project scope)

### Weeks Later

```
You: "What were our architecture decisions for this project?"

Claude: [calls memory.decisions]

"Here are the architectural decisions I have on record:

1. **Architecture Pattern**: Microservices architecture
2. **Authentication**: JWT authentication
3. **API Style**: REST APIs for service communication

These decisions were made during the initial project planning."
```

**What happened:**
- Semantic shortcut `memory.decisions` provides quick access
- No need to manually construct search queries
- Pre-configured to find decision-related facts

---

## Example 4: Privacy Control

**Scenario:** Working with sensitive credentials

### The Conversation

```
You: "Our API endpoint is https://api.example.com with key <private>sk-abc123</private>
      and secret <private>secret_xyz</private>"

Claude: "I'll configure the API client with those credentials..."

[Claude uses the credentials during the session to help set up API calls]
```

### Behind the Scenes

**What gets stored:**
```
"API endpoint is https://api.example.com with key  and secret "
```

**What does NOT get stored:**
- ❌ `sk-abc123`
- ❌ `secret_xyz`

**Privacy tags stripped at ingestion** - zero chance of leaking in future queries.

### Later Session

```
You: "What's our API configuration?"

Claude: [calls memory.recall]

"According to my memory, your API endpoint is https://api.example.com.
You'll need to provide the key and secret again as I don't store sensitive credentials."
```

---

## Example 5: Semantic Shortcuts

**Scenario:** Quick access to common information

### Conventions Query

```
You: "What coding conventions do I follow?"

Claude: [calls memory.conventions]

"Here are your coding conventions:

• 4-space indentation
• Descriptive variable names over abbreviations
• RSpec for testing (not Minitest)
• Standard Ruby for linting
• Prefer composition over inheritance"
```

**What happened:**
- `memory.conventions` is a semantic shortcut
- Pre-configured to search for convention-related predicates
- Returns results instantly without manual query construction

### Architecture Query

```
You: "Remind me what frameworks we're using"

Claude: [calls memory.architecture]

"Your tech stack:

**Frontend:**
• Framework: React 18
• State Management: Redux Toolkit
• Styling: Tailwind CSS

**Backend:**
• Framework: Rails 7
• Database: PostgreSQL
• Deployment: Heroku"
```

### Decisions Query

```
You: "What architectural decisions have we made?"

Claude: [calls memory.decisions]

"Key architectural decisions:

1. Microservices architecture
2. JWT authentication
3. REST APIs for service communication
4. Event-driven updates with webhooks"
```

---

## Example 6: Progressive Disclosure

**Scenario:** Token-efficient memory searches

### Initial Query (Lightweight)

```
Claude: [calls memory.recall_index with query="database"]

# Returns lightweight index (~50 tokens per fact):
# - Fact ID: 42, Preview: "uses_database: PostgreSQL"
# - Fact ID: 78, Preview: "database_host: AWS RDS"
# - Fact ID: 103, Preview: "convention: Always use parameterized queries"
# - Fact ID: 145, Preview: "decision: Use connection pooling"
# - Fact ID: 189, Preview: "uses_database: Redis for caching"

Claude: "I found several facts about databases in your project:
        • PostgreSQL as primary database
        • AWS RDS for hosting
        • Redis for caching
        • Connection pooling enabled
        • Parameterized queries convention

        Would you like details on any specific item?"
```

### Detailed Query (On Demand)

```
You: "Tell me more about the PostgreSQL setup"

Claude: [calls memory.recall_details with fact_id=42]

# Returns full details with provenance:
# - Subject: repo
# - Predicate: uses_database
# - Object: PostgreSQL
# - Quote: "I'm starting a new Rails 7 project with PostgreSQL"
# - Source: Session abc-123, 2026-01-15
# - Superseded from: MySQL (Fact ID: 39)
# - Related: 3 other database facts

Claude: "You're using PostgreSQL as your primary database. This decision was made
        on 2026-01-15 when starting the Rails 7 project. It replaced a previous
        MySQL configuration."
```

**Token Savings:**
- Initial search: ~250 tokens (5 facts × 50 tokens)
- Without progressive disclosure: ~2,500 tokens (5 facts × 500 tokens)
- **10x reduction!**

---

## Example 7: Conflict Resolution

**Scenario:** Handling contradictory information

### Day 1

```
You: "We're using PostgreSQL for this project"

Claude: "Got it, storing that in memory."
```

**Stored:** `uses_database: PostgreSQL`

### Day 5

```
You: "Actually, we switched to MySQL for better compatibility"

Claude: "I'll update my memory to reflect that database change."
```

### Behind the Scenes

ClaudeMemory automatically:
1. **Creates new fact**: `uses_database: MySQL`
2. **Marks old fact as superseded**: `uses_database: PostgreSQL` (superseded by Fact #78)
3. **Maintains temporal validity**:
   - PostgreSQL valid from 2026-01-15 to 2026-01-20
   - MySQL valid from 2026-01-20 onwards

### Query Later

```
You: "What database are we using?"

Claude: [calls memory.recall]

"You're currently using MySQL. You previously used PostgreSQL but switched
to MySQL on 2026-01-20 for better compatibility."
```

**What happened:**
- Truth maintenance handled supersession automatically
- No duplicates or conflicts
- Historical context preserved
- Current fact returned by default

---

## Example 8: Team Workflow

**Scenario:** Sharing memory across team members (advanced)

### Developer A's Session

```
Developer A: "We decided to use Stripe for payments and store webhooks in the
             payment_events table"

Claude: [stores decision]
```

### Developer B's Session (Same Project)

```
Developer B: "How do we handle payment webhooks?"

Claude: [recalls project facts]

"According to the project's memory, you're using Stripe for payments and storing
webhooks in the payment_events table."
```

**How it works:**
- Project-scoped facts stored in `.claude/memory.sqlite3`
- Committed to git (optional)
- Shared across team members
- Provides consistency and context for everyone

---

## Example 9: Migration Workflow

**Scenario:** Migrating from one technology to another

### Before Migration

```
Memory contains:
• uses_framework: React (class components)
• state_management: Redux
```

### During Migration

```
You: "We're migrating to React hooks and removing Redux in favor of Context API"

Claude: "I'll help with the migration and update my memory accordingly."

[Claude helps refactor components]
```

### After Migration

```
Memory now contains:
• uses_framework: React (hooks) [superseded React class components]
• state_management: Context API [superseded Redux]

Historical facts preserved with temporal validity:
• Redux valid from 2025-06-01 to 2026-01-22
• Context API valid from 2026-01-22 onwards
```

### Future Queries

```
You: "What state management do we use?"

Claude: "You're using Context API for state management. You previously used Redux
        but migrated to Context API on 2026-01-22."
```

---

## Tips for Effective Memory Usage

### ✅ Do This

- **Be specific**: "We're using PostgreSQL 14" is better than "We're using a database"
- **State preferences clearly**: "I always prefer X" signals global scope
- **Use privacy tags**: `<private>sensitive-data</private>` for secrets
- **Review decisions**: Periodically ask "What do you remember about this project?"

### ❌ Avoid This

- **Don't repeat facts**: ClaudeMemory handles duplicates automatically
- **Don't worry about formatting**: Natural conversation works best
- **Don't manually manage memory**: Let Claude handle extraction
- **Don't store temporary info**: Only durable facts are worth remembering

---

## Next Steps

- 📖 [Read the Getting Started Guide](GETTING_STARTED.md) *(coming soon)*
- 🔧 [Set up the Claude Code Plugin](PLUGIN.md)
- 🏗️ [Understand the Architecture](architecture.md)
- 📝 [Check the Changelog](../CHANGELOG.md)
