# Focused Analysis Examples

When using the `--focus` flag, narrow the analysis to specific aspects of the repository. This is especially useful for:
- Very large repositories (>5000 files)
- Time-constrained analysis
- Specific adoption goals
- Deep study of one component

## How Focus Mode Works

1. **Narrows file exploration** to relevant paths only
2. **Focuses comparison** on the specific aspect
3. **Targets recommendations** to the focused area
4. **Reduces context usage** for faster analysis
5. **Produces smaller** influence documents

## Example Focus Topics

### Testing Strategy

```bash
/study-repo /tmp/repo --focus="testing strategy"
```

**What to analyze**:
- Test files and directory structure (spec/, test/)
- Test framework choice (RSpec, Minitest, etc.)
- CI configuration (.github/workflows/, .circleci/)
- Test coverage tools and reporting
- Mocking/stubbing patterns
- Integration vs unit test balance
- Test factories and fixtures
- Performance test practices

**Output focus**:
- How they organize tests
- What patterns they use for test data
- How they achieve high coverage
- CI/CD testing pipeline design

---

### MCP Integration

```bash
/study-repo /tmp/repo --focus="MCP server implementation"
```

**What to analyze**:
- MCP server files (mcp/, server/)
- Tool definitions and schemas
- Request/response handling
- Error handling approach
- Tool composition and organization
- JSON-RPC implementation
- Streaming support
- Authentication/security

**Output focus**:
- How tools are structured
- Best practices for tool design
- Error handling patterns
- Performance optimizations

---

### Database Schema

```bash
/study-repo /tmp/repo --focus="database design"
```

**What to analyze**:
- Schema files (db/schema.rb, migrations/)
- Index strategies
- Query optimization patterns
- Transaction management
- Connection pooling
- Database abstraction layer
- Migration practices
- Backup/restore approaches

**Output focus**:
- Schema design decisions
- Performance optimizations
- Migration safety patterns
- Query efficiency techniques

---

### CLI Architecture

```bash
/study-repo /tmp/repo --focus="CLI design"
```

**What to analyze**:
- Entry points (bin/, exe/)
- Command organization (commands/, lib/commands/)
- Argument parsing (Thor, OptionParser, etc.)
- Help text and documentation
- Error messages and exit codes
- Subcommand structure
- Configuration file handling
- Output formatting

**Output focus**:
- Command organization patterns
- User experience considerations
- Error handling best practices
- Testing CLI commands

---

### Performance Optimizations

```bash
/study-repo /tmp/repo --focus="performance"
```

**What to analyze**:
- Caching strategies (Redis, in-memory)
- Batch processing patterns
- Query optimization
- Resource management
- Profiling and metrics
- Lazy loading techniques
- Memory efficiency
- Concurrency patterns

**Output focus**:
- What they optimize and how
- Benchmarking approaches
- Trade-offs made
- Performance monitoring

---

### Error Handling

```bash
/study-repo /tmp/repo --focus="error handling"
```

**What to analyze**:
- Exception hierarchy
- Error class organization
- Recovery strategies
- User-facing error messages
- Logging practices
- Retry logic
- Graceful degradation
- Error reporting/telemetry

**Output focus**:
- Exception design patterns
- Error communication to users
- Debugging support
- Resilience patterns

---

### Configuration Management

```bash
/study-repo /tmp/repo --focus="configuration"
```

**What to analyze**:
- Config file formats (YAML, JSON, TOML)
- Environment variable handling
- Default value strategies
- Configuration validation
- Secret management
- Multi-environment support
- Configuration discovery
- Override precedence

**Output focus**:
- Configuration architecture
- Validation and defaults
- Security practices
- User experience

---

### Domain Modeling

```bash
/study-repo /tmp/repo --focus="domain model"
```

**What to analyze**:
- Core domain objects
- Value objects vs entities
- Aggregate boundaries
- Repository pattern usage
- Domain events
- Business logic organization
- Validation rules
- Domain services

**Output focus**:
- How domain is modeled
- Separation of concerns
- Business rule implementation
- Pattern usage

---

### Dependency Injection

```bash
/study-repo /tmp/repo --focus="dependency injection"
```

**What to analyze**:
- DI container (if any)
- Constructor injection patterns
- Service locator usage
- Factory patterns
- Testability approaches
- Configuration of dependencies
- Lifecycle management
- Interface abstractions

**Output focus**:
- DI strategy and patterns
- Testing benefits
- Complexity vs benefits
- Best practices

---

### API Design

```bash
/study-repo /tmp/repo --focus="API design"
```

**What to analyze**:
- REST/GraphQL/RPC patterns
- Endpoint organization
- Request/response formats
- Versioning strategy
- Authentication/authorization
- Rate limiting
- Documentation (OpenAPI, etc.)
- Client SDK design

**Output focus**:
- API structure and conventions
- Versioning approach
- Documentation practices
- Client experience

---

## Custom Focus Topics

You can specify any aspect you want to focus on:

```bash
/study-repo /tmp/repo --focus="logging and observability"
/study-repo /tmp/repo --focus="file system abstraction"
/study-repo /tmp/repo --focus="plugin architecture"
/study-repo /tmp/repo --focus="webhook handling"
```

The skill will adapt the analysis to your specified topic.

## When to Use Focus Mode

### Use Focus When:
- Repository has >1000 files
- You have a specific adoption goal
- You want deep analysis of one aspect
- Time is limited
- You're comparing specific features

### Use Full Analysis When:
- Repository is small (<500 files)
- You want comprehensive overview
- Architecture understanding is the goal
- Time allows for thorough exploration
- Making major adoption decisions

## Output Differences

### Full Analysis Output:
```
docs/influence/project-name.md
- All sections populated
- Broad recommendations
- Comprehensive comparison
- 10-20 pages typical
```

### Focused Analysis Output:
```
docs/influence/project-name-focus.md
- Focused sections only
- Targeted recommendations
- Specific comparison
- 3-8 pages typical
```

## Combining Focuses

For very large projects, run multiple focused analyses:

```bash
# Study different aspects separately
/study-repo /tmp/big-repo --focus="MCP implementation"
/study-repo /tmp/big-repo --focus="testing strategy"
/study-repo /tmp/big-repo --focus="database design"
```

Each produces a separate influence document focused on that aspect.

## Tips for Effective Focus

1. **Be specific**: "MCP server" is better than "server stuff"
2. **Match their terminology**: Use terms from their docs/code
3. **Start broad, then focus**: Run full analysis first to identify interesting areas
4. **Combine with grep**: Search for keywords related to your focus
5. **Review examples**: Look at their tests for the focused component
