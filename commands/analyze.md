---
description: Analyze project and store facts in memory
disable-model-invocation: true
---

Analyze this project to understand its tech stack, frameworks, tools, and conventions.

## Steps

1. Read key project files (if they exist):
   - `Gemfile`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`
   - `README.md`, `tsconfig.json`, `Dockerfile`
   - `.eslintrc*`, `.prettierrc*`, `.rubocop.yml`, `.standard.yml`
   - `.github/workflows/*.yml`

2. Extract facts about:
   - Languages (Ruby, TypeScript, Python, Go, Rust)
   - Frameworks (Rails, React, Next.js, Django, FastAPI)
   - Tools (RSpec, Jest, ESLint, Prettier, Docker)
   - Databases (PostgreSQL, MySQL, Redis, MongoDB)
   - Package managers (Bundler, npm, pnpm, Poetry, Cargo)
   - CI/CD (GitHub Actions, CircleCI, GitLab CI)

3. Use `memory.store_extraction` to store facts with:
   - Appropriate entity types and predicates
   - Quotes referencing the source file/line
   - `strength: "stated"` for explicit declarations

4. Report what you learned and stored.
