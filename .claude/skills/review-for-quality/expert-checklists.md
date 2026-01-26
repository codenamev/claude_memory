# Expert Review Checklists

## Sandi Metz (POODR) Checklist

- [ ] Classes under 100 lines
- [ ] Methods under 5 lines
- [ ] Method parameters limited (< 4)
- [ ] Single Responsibility Principle followed
- [ ] No god objects (classes > 500 lines)
- [ ] DRY violations eliminated
- [ ] Dependencies injected, not created
- [ ] Public interface is minimal
- [ ] Private methods grouped at bottom
- [ ] attr_reader used appropriately

## Jeremy Evans (Sequel) Checklist

- [ ] Using Sequel datasets, not raw SQL
- [ ] Transactions wrap multi-step operations
- [ ] DateTime columns instead of String timestamps
- [ ] Sequel migrations used (not manual)
- [ ] Connection pooling configured
- [ ] Sequel plugins utilized (timestamps, validation_helpers)
- [ ] No N+1 query patterns
- [ ] Batch queries used for multiple records
- [ ] Foreign keys defined properly
- [ ] Indexes created for common queries

## Kent Beck (TDD, Simple Design) Checklist

- [ ] Dependencies can be injected for testing
- [ ] No side effects in constructors
- [ ] Methods reveal intent through naming
- [ ] Complex boolean logic is extracted and named
- [ ] No large case statements (use polymorphism)
- [ ] Tests exist for failure modes
- [ ] Command-Query Separation followed
- [ ] Simple solutions chosen over complex ones
- [ ] Test coverage for edge cases
- [ ] Clear boundaries between components

## Avdi Grimm (Confident Ruby) Checklist

- [ ] Null Object pattern used instead of nil checks
- [ ] Consistent return values (not mixed types)
- [ ] Result objects for success/failure
- [ ] Tell, don't ask (no ask-then-do patterns)
- [ ] Early returns minimized (use guard clauses)
- [ ] Primitive obsession eliminated (use value objects)
- [ ] Domain objects instead of hashes
- [ ] Duck typing enables polymorphism
- [ ] Meaningful default values
- [ ] Confident code (no defensive programming everywhere)

## Gary Bernhardt (Boundaries) Checklist

- [ ] I/O separated from business logic
- [ ] Core logic is pure (no side effects)
- [ ] Fast unit tests (no database/filesystem)
- [ ] Value objects used for domain concepts
- [ ] State passed as parameters, not stored in instance variables
- [ ] Clear layer boundaries (presentation → application → domain → infrastructure)
- [ ] File I/O abstracted (dependency injection)
- [ ] Database access abstracted (repository pattern)
- [ ] Functional core, imperative shell pattern
- [ ] Immutable data structures preferred

## General Ruby Idioms Checklist

- [ ] frozen_string_literal: true in all files
- [ ] Consistent method parentheses style
- [ ] Keyword arguments for methods with > 2 params
- [ ] Parameter objects for long parameter lists
- [ ] Consistent hash access (symbols vs strings)
- [ ] Specific exception rescues (not bare rescue)
- [ ] ENV access centralized
- [ ] Boolean traps eliminated (use explicit values)
- [ ] Ruby 3 features used where appropriate
- [ ] Standard Ruby linter passing
