# frozen_string_literal: true

require "fileutils"

module ClaudeMemory
  module Commands
    module Initializers
      # Writes ClaudeMemory instructions to CLAUDE.md files
      class MemoryInstructionsWriter
        def initialize(stdout)
          @stdout = stdout
        end

        def write_project_instructions
          claude_dir = ".claude"
          claude_md_path = File.join(claude_dir, "CLAUDE.md")

          memory_instruction = <<~MD
            <!-- ClaudeMemory v#{ClaudeMemory::VERSION} -->
            # ClaudeMemory

            This project has ClaudeMemory enabled for both project-specific and global knowledge.

            ## Memory-First Workflow

            **IMPORTANT: Check memory BEFORE reading files or exploring code.**

            ### Workflow Pattern

            1. **Query memory first**: `memory.recall "<topic>"` or use shortcuts
            2. **Review results**: Understand existing knowledge and decisions
            3. **Explore if needed**: Use Read/Grep only if memory is insufficient
            4. **Combine context**: Merge recalled facts with code exploration

            ### Specialized Shortcuts

            - `memory.decisions` - Project decisions (ALWAYS check before implementing)
            - `memory.conventions` - Global coding preferences
            - `memory.architecture` - Framework choices and patterns
            - `memory.conflicts` - Contradictions that need resolution

            ### Scope Awareness

            - **Project facts**: Apply only to this project (e.g., "uses PostgreSQL")
            - **Global facts**: Apply everywhere (e.g., "prefers 4-space tabs")
            - Use `scope: "project"` or `scope: "global"` to filter queries

            ### When Memory Helps Most

            - "Where is X handled?" → `memory.recall "X handling"`
            - "How do we do Y?" → `memory.recall "Y pattern"`
            - "Why did we choose Z?" → `memory.decisions`
            - Before writing code → `memory.conventions`

            See published snapshot: `.claude/rules/claude_memory.generated.md`
          MD

          FileUtils.mkdir_p(claude_dir)
          if File.exist?(claude_md_path)
            content = File.read(claude_md_path)
            unless content.include?("ClaudeMemory")
              File.write(claude_md_path, content + "\n\n" + memory_instruction)
            end
          else
            File.write(claude_md_path, memory_instruction)
          end

          @stdout.puts "✓ Updated #{claude_md_path}"
        end

        def write_global_instructions
          global_claude_dir = File.join(Dir.home, ".claude")
          claude_md_path = File.join(global_claude_dir, "CLAUDE.md")

          memory_instruction = <<~MD
            <!-- ClaudeMemory v#{ClaudeMemory::VERSION} -->
            # ClaudeMemory

            ClaudeMemory provides long-term memory across all your sessions.

            ## Memory-First Workflow

            **IMPORTANT: Always check memory BEFORE reading files or exploring code.**

            When you receive a question or task:
            1. **First**: Use `memory.recall` with a relevant query
            2. **Then**: If memory is insufficient, explore with Read/Grep/Glob
            3. **Combine**: Use recalled facts + code exploration for complete context

            ### When to Check Memory

            - Before answering "How does X work?" questions
            - Before implementing features (check for patterns and decisions)
            - Before debugging (check for known issues)
            - When you make a mistake (recall correct approach)

            ### Quick-Access Tools

            - `memory.recall` - General knowledge search (USE THIS FIRST)
            - `memory.decisions` - Architectural decisions and constraints
            - `memory.conventions` - Coding style and preferences
            - `memory.architecture` - Framework and pattern choices
            - `memory.explain` - Detailed provenance for specific facts
            - `memory.conflicts` - Open contradictions
            - `memory.status` - System health check

            ### Example Queries

            ```
            memory.recall "authentication flow"
            memory.recall "error handling patterns"
            memory.recall "database setup"
            memory.decisions (before implementing features)
            memory.conventions (before writing code)
            ```

            The memory system contains distilled knowledge from previous sessions. Using it saves time and provides better answers.
          MD

          FileUtils.mkdir_p(global_claude_dir)
          if File.exist?(claude_md_path)
            content = File.read(claude_md_path)
            unless content.include?("ClaudeMemory")
              File.write(claude_md_path, content + "\n\n" + memory_instruction)
            end
          else
            File.write(claude_md_path, memory_instruction)
          end

          @stdout.puts "✓ Updated #{claude_md_path}"
        end
      end
    end
  end
end
