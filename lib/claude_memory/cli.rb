# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  class CLI
    COMMANDS = %w[help version db:init].freeze

    def initialize(args = ARGV, stdout: $stdout, stderr: $stderr, stdin: $stdin)
      @args = args
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
    end

    def run
      command = @args.first || "help"

      case command
      when "help", "-h", "--help"
        print_help
        0
      when "version", "-v", "--version"
        print_version
        0
      when "db:init"
        db_init
        0
      when "init"
        init_project
      when "ingest"
        ingest
      when "search"
        search
      when "recall"
        recall_cmd
      when "explain"
        explain_cmd
      when "conflicts"
        conflicts_cmd
      when "changes"
        changes_cmd
      when "sweep"
        sweep_cmd
      when "serve-mcp"
        serve_mcp
      when "publish"
        publish_cmd
      when "hook"
        hook_cmd
      when "doctor"
        doctor_cmd
      when "promote"
        promote_cmd
      else
        @stderr.puts "Unknown command: #{command}"
        @stderr.puts "Run 'claude-memory help' for usage."
        1
      end
    end

    private

    def print_help
      @stdout.puts <<~HELP
        claude-memory - Long-term memory for Claude Code

        Usage: claude-memory <command> [options]

        Commands:
          changes    Show recent fact changes
          conflicts  Show open conflicts
          db:init    Initialize the SQLite database
          doctor     Check system health
          explain    Explain a fact with receipts
          help       Show this help message
          hook       Run hook entrypoints (ingest|sweep|publish)
          init       Initialize ClaudeMemory in a project
          ingest     Ingest transcript delta
          promote    Promote a project fact to global memory
          publish    Publish snapshot to Claude Code memory
          recall     Recall facts matching a query
          search     Search indexed content
          serve-mcp  Start MCP server
          sweep      Run maintenance/pruning
          version    Show version number

        Run 'claude-memory <command> --help' for more information on a command.
      HELP
    end

    def print_version
      @stdout.puts "claude-memory #{ClaudeMemory::VERSION}"
    end

    def db_init
      opts = parse_db_init_options
      manager = ClaudeMemory::Store::StoreManager.new

      if opts[:global]
        manager.ensure_global!
        @stdout.puts "Global database initialized at #{manager.global_db_path}"
        @stdout.puts "Schema version: #{manager.global_store.schema_version}"
      end

      if opts[:project]
        manager.ensure_project!
        @stdout.puts "Project database initialized at #{manager.project_db_path}"
        @stdout.puts "Schema version: #{manager.project_store.schema_version}"
      end

      manager.close
    end

    def parse_db_init_options
      opts = {global: false, project: false}

      parser = OptionParser.new do |o|
        o.banner = "Usage: claude-memory db:init [options]"
        o.on("--global", "Initialize global database (~/.claude/memory.sqlite3)") { opts[:global] = true }
        o.on("--project", "Initialize project database (.claude/memory.sqlite3)") { opts[:project] = true }
      end

      parser.parse!(@args[1..])

      opts[:global] = true if !opts[:global] && !opts[:project]
      opts[:project] = true if !opts[:global] && !opts[:project]

      opts
    end

    def ingest
      opts = parse_ingest_options
      return 1 unless opts

      store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
      ingester = ClaudeMemory::Ingest::Ingester.new(store)

      result = ingester.ingest(
        source: opts[:source],
        session_id: opts[:session_id],
        transcript_path: opts[:transcript_path]
      )

      case result[:status]
      when :ingested
        @stdout.puts "Ingested #{result[:bytes_read]} bytes (content_id: #{result[:content_id]})"
      when :no_change
        @stdout.puts "No new content to ingest"
      end

      store.close
      0
    rescue ClaudeMemory::Ingest::TranscriptReader::FileNotFoundError => e
      @stderr.puts "Error: #{e.message}"
      1
    end

    def parse_ingest_options
      opts = {source: "claude_code", db: ClaudeMemory.project_db_path}

      parser = OptionParser.new do |o|
        o.banner = "Usage: claude-memory ingest [options]"
        o.on("--source SOURCE", "Source identifier (default: claude_code)") { |v| opts[:source] = v }
        o.on("--session-id ID", "Session identifier (required)") { |v| opts[:session_id] = v }
        o.on("--transcript-path PATH", "Path to transcript file (required)") { |v| opts[:transcript_path] = v }
        o.on("--db PATH", "Database path") { |v| opts[:db] = v }
      end

      parser.parse!(@args[1..])

      unless opts[:session_id] && opts[:transcript_path]
        @stderr.puts parser.help
        @stderr.puts "\nError: --session-id and --transcript-path are required"
        return nil
      end

      opts
    end

    def search
      query = @args[1]
      unless query
        @stderr.puts "Usage: claude-memory search <query> [--db PATH] [--limit N]"
        return 1
      end

      opts = {limit: 10, scope: "all"}
      OptionParser.new do |o|
        o.on("--limit N", Integer, "Max results") { |v| opts[:limit] = v }
        o.on("--scope SCOPE", "Scope: project, global, or all") { |v| opts[:scope] = v }
      end.parse!(@args[2..])

      manager = ClaudeMemory::Store::StoreManager.new
      store = manager.store_for_scope((opts[:scope] == "global") ? "global" : "project")
      fts = ClaudeMemory::Index::LexicalFTS.new(store)

      ids = fts.search(query, limit: opts[:limit])
      if ids.empty?
        @stdout.puts "No results found."
      else
        @stdout.puts "Found #{ids.size} result(s):"
        ids.each do |id|
          text = store.content_items.where(id: id).get(:raw_text)
          preview = text&.slice(0, 100)&.gsub(/\s+/, " ")
          @stdout.puts "  [#{id}] #{preview}..."
        end
      end

      manager.close
      0
    end

    def recall_cmd
      query = @args[1]
      unless query
        @stderr.puts "Usage: claude-memory recall <query> [--limit N] [--scope project|global|all]"
        return 1
      end

      opts = {limit: 10, scope: "all"}
      OptionParser.new do |o|
        o.on("--limit N", Integer, "Max results") { |v| opts[:limit] = v }
        o.on("--scope SCOPE", "Scope: project, global, or all") { |v| opts[:scope] = v }
      end.parse!(@args[2..])

      manager = ClaudeMemory::Store::StoreManager.new
      recall = ClaudeMemory::Recall.new(manager)

      results = recall.query(query, limit: opts[:limit], scope: opts[:scope])
      if results.empty?
        @stdout.puts "No facts found."
      else
        @stdout.puts "Found #{results.size} fact(s):\n\n"
        results.each do |result|
          print_fact(result[:fact], source: result[:source])
          print_receipts(result[:receipts])
          @stdout.puts
        end
      end

      manager.close
      0
    end

    def explain_cmd
      fact_id = @args[1]&.to_i
      unless fact_id && fact_id > 0
        @stderr.puts "Usage: claude-memory explain <fact_id> [--scope project|global]"
        return 1
      end

      opts = {scope: "project"}
      OptionParser.new do |o|
        o.on("--scope SCOPE", "Scope: project or global") { |v| opts[:scope] = v }
      end.parse!(@args[2..])

      manager = ClaudeMemory::Store::StoreManager.new
      recall = ClaudeMemory::Recall.new(manager)

      explanation = recall.explain(fact_id, scope: opts[:scope])
      if explanation.nil?
        @stderr.puts "Fact #{fact_id} not found in #{opts[:scope]} database."
        manager.close
        return 1
      end

      @stdout.puts "Fact ##{fact_id} (#{opts[:scope]}):"
      print_fact(explanation[:fact])
      print_receipts(explanation[:receipts])

      if explanation[:supersedes].any?
        @stdout.puts "  Supersedes: #{explanation[:supersedes].join(", ")}"
      end
      if explanation[:superseded_by].any?
        @stdout.puts "  Superseded by: #{explanation[:superseded_by].join(", ")}"
      end
      if explanation[:conflicts].any?
        @stdout.puts "  Conflicts: #{explanation[:conflicts].map { |c| c[:id] }.join(", ")}"
      end

      manager.close
      0
    end

    def conflicts_cmd
      opts = {scope: "all"}
      OptionParser.new do |o|
        o.on("--scope SCOPE", "Scope: project, global, or all") { |v| opts[:scope] = v }
      end.parse!(@args[1..])

      manager = ClaudeMemory::Store::StoreManager.new
      recall = ClaudeMemory::Recall.new(manager)
      conflicts = recall.conflicts(scope: opts[:scope])

      if conflicts.empty?
        @stdout.puts "No open conflicts."
      else
        @stdout.puts "Open conflicts (#{conflicts.size}):\n\n"
        conflicts.each do |c|
          source_label = c[:source] ? " [#{c[:source]}]" : ""
          @stdout.puts "  Conflict ##{c[:id]}: Fact #{c[:fact_a_id]} vs Fact #{c[:fact_b_id]}#{source_label}"
          @stdout.puts "    Status: #{c[:status]}, Detected: #{c[:detected_at]}"
          @stdout.puts "    Notes: #{c[:notes]}" if c[:notes]
          @stdout.puts
        end
      end

      manager.close
      0
    end

    def changes_cmd
      opts = {since: nil, limit: 20, scope: "all"}
      OptionParser.new do |o|
        o.on("--since ISO", "Since timestamp") { |v| opts[:since] = v }
        o.on("--limit N", Integer, "Max results") { |v| opts[:limit] = v }
        o.on("--scope SCOPE", "Scope: project, global, or all") { |v| opts[:scope] = v }
      end.parse!(@args[1..])

      opts[:since] ||= (Time.now - 86400 * 7).utc.iso8601

      manager = ClaudeMemory::Store::StoreManager.new
      recall = ClaudeMemory::Recall.new(manager)

      changes = recall.changes(since: opts[:since], limit: opts[:limit], scope: opts[:scope])
      if changes.empty?
        @stdout.puts "No changes since #{opts[:since]}."
      else
        @stdout.puts "Changes since #{opts[:since]} (#{changes.size}):\n\n"
        changes.each do |change|
          source_label = change[:source] ? " [#{change[:source]}]" : ""
          @stdout.puts "  [#{change[:id]}] #{change[:predicate]}: #{change[:object_literal]} (#{change[:status]})#{source_label}"
          @stdout.puts "    Created: #{change[:created_at]}"
        end
      end

      manager.close
      0
    end

    def print_fact(fact, source: nil)
      source_label = source ? " [#{source}]" : ""
      @stdout.puts "  #{fact[:subject_name]}.#{fact[:predicate]} = #{fact[:object_literal]}#{source_label}"
      @stdout.puts "    Status: #{fact[:status]}, Confidence: #{fact[:confidence]}"
      @stdout.puts "    Valid: #{fact[:valid_from]} - #{fact[:valid_to] || "present"}"
    end

    def print_receipts(receipts)
      return if receipts.empty?

      @stdout.puts "  Receipts:"
      receipts.each do |r|
        quote_preview = r[:quote]&.slice(0, 80)&.gsub(/\s+/, " ")
        @stdout.puts "    - [#{r[:strength]}] \"#{quote_preview}...\""
      end
    end

    def sweep_cmd
      opts = {budget: 5, scope: "project"}
      OptionParser.new do |o|
        o.on("--budget SECONDS", Integer, "Time budget in seconds") { |v| opts[:budget] = v }
        o.on("--scope SCOPE", "Scope: project or global") { |v| opts[:scope] = v }
      end.parse!(@args[1..])

      manager = ClaudeMemory::Store::StoreManager.new
      store = manager.store_for_scope(opts[:scope])
      sweeper = ClaudeMemory::Sweep::Sweeper.new(store)

      @stdout.puts "Running sweep on #{opts[:scope]} database with #{opts[:budget]}s budget..."
      stats = sweeper.run!(budget_seconds: opts[:budget])

      @stdout.puts "Sweep complete:"
      @stdout.puts "  Proposed facts expired: #{stats[:proposed_facts_expired]}"
      @stdout.puts "  Disputed facts expired: #{stats[:disputed_facts_expired]}"
      @stdout.puts "  Orphaned provenance deleted: #{stats[:orphaned_provenance_deleted]}"
      @stdout.puts "  Old content pruned: #{stats[:old_content_pruned]}"
      @stdout.puts "  Elapsed: #{stats[:elapsed_seconds].round(2)}s"
      @stdout.puts "  Budget honored: #{stats[:budget_honored]}"

      manager.close
      0
    end

    def serve_mcp
      manager = ClaudeMemory::Store::StoreManager.new
      server = ClaudeMemory::MCP::Server.new(manager)
      server.run
      manager.close
      0
    end

    def publish_cmd
      opts = {mode: :shared, granularity: :repo, since: nil, scope: "project"}
      OptionParser.new do |o|
        o.on("--mode MODE", "Mode: shared, local, or home") { |v| opts[:mode] = v.to_sym }
        o.on("--granularity LEVEL", "Granularity: repo, paths, or nested") { |v| opts[:granularity] = v.to_sym }
        o.on("--since ISO", "Include changes since timestamp") { |v| opts[:since] = v }
        o.on("--scope SCOPE", "Scope: project or global") { |v| opts[:scope] = v }
      end.parse!(@args[1..])

      manager = ClaudeMemory::Store::StoreManager.new
      store = manager.store_for_scope(opts[:scope])
      publish = ClaudeMemory::Publish.new(store)

      result = publish.publish!(mode: opts[:mode], granularity: opts[:granularity], since: opts[:since])

      case result[:status]
      when :updated
        @stdout.puts "Published #{opts[:scope]} snapshot to #{result[:path]}"
      when :unchanged
        @stdout.puts "No changes - #{result[:path]} is up to date"
      end

      manager.close
      0
    end

    def promote_cmd
      fact_id = @args[1]&.to_i
      unless fact_id && fact_id > 0
        @stderr.puts "Usage: claude-memory promote <fact_id>"
        @stderr.puts "\nPromotes a project fact to the global database."
        return 1
      end

      manager = ClaudeMemory::Store::StoreManager.new
      global_fact_id = manager.promote_fact(fact_id)

      if global_fact_id
        @stdout.puts "Promoted fact ##{fact_id} to global database as fact ##{global_fact_id}"
      else
        @stderr.puts "Fact ##{fact_id} not found in project database."
        manager.close
        return 1
      end

      manager.close
      0
    end

    def hook_cmd
      subcommand = @args[1]

      unless subcommand
        @stderr.puts "Usage: claude-memory hook <ingest|sweep|publish> [options]"
        @stderr.puts "\nReads hook payload JSON from stdin."
        return 1
      end

      unless %w[ingest sweep publish].include?(subcommand)
        @stderr.puts "Unknown hook command: #{subcommand}"
        @stderr.puts "Available: ingest, sweep, publish"
        return 1
      end

      opts = {db: ClaudeMemory.project_db_path}
      OptionParser.new do |o|
        o.on("--db PATH", "Database path") { |v| opts[:db] = v }
      end.parse!(@args[2..])

      payload = parse_hook_payload
      return 1 unless payload

      store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
      handler = ClaudeMemory::Hook::Handler.new(store)

      case subcommand
      when "ingest"
        hook_ingest(handler, payload)
      when "sweep"
        hook_sweep(handler, payload)
      when "publish"
        hook_publish(handler, payload)
      end

      store.close
      0
    rescue ClaudeMemory::Hook::Handler::PayloadError => e
      @stderr.puts "Payload error: #{e.message}"
      1
    rescue ClaudeMemory::Ingest::TranscriptReader::FileNotFoundError => e
      @stderr.puts "Error: #{e.message}"
      1
    end

    def parse_hook_payload
      input = @stdin.read
      JSON.parse(input)
    rescue JSON::ParserError => e
      @stderr.puts "Invalid JSON payload: #{e.message}"
      nil
    end

    def hook_ingest(handler, payload)
      result = handler.ingest(payload)

      case result[:status]
      when :ingested
        @stdout.puts "Ingested #{result[:bytes_read]} bytes (content_id: #{result[:content_id]})"
      when :no_change
        @stdout.puts "No new content to ingest"
      end
    end

    def hook_sweep(handler, payload)
      result = handler.sweep(payload)
      stats = result[:stats]

      @stdout.puts "Sweep complete:"
      @stdout.puts "  Elapsed: #{stats[:elapsed_seconds].round(2)}s"
      @stdout.puts "  Budget honored: #{stats[:budget_honored]}"
    end

    def hook_publish(handler, payload)
      result = handler.publish(payload)

      case result[:status]
      when :updated
        @stdout.puts "Published snapshot to #{result[:path]}"
      when :unchanged
        @stdout.puts "No changes - #{result[:path]} is up to date"
      end
    end

    def init_project
      opts = {global: false}
      OptionParser.new do |o|
        o.on("--global", "Install to global ~/.claude/ settings") { opts[:global] = true }
      end.parse!(@args[1..])

      if opts[:global]
        init_global
      else
        init_local
      end
    end

    def init_local
      @stdout.puts "Initializing ClaudeMemory (project-local)...\n\n"

      manager = ClaudeMemory::Store::StoreManager.new
      manager.ensure_global!
      @stdout.puts "✓ Global database: #{manager.global_db_path}"
      manager.ensure_project!
      @stdout.puts "✓ Project database: #{manager.project_db_path}"
      manager.close

      FileUtils.mkdir_p(".claude/rules")
      @stdout.puts "✓ Created .claude/rules directory"

      configure_project_hooks
      configure_project_mcp
      install_output_style

      @stdout.puts "\n=== Setup Complete ===\n"
      @stdout.puts "ClaudeMemory is now configured for this project."
      @stdout.puts "\nDatabases:"
      @stdout.puts "  Global: ~/.claude/memory.sqlite3 (user-wide knowledge)"
      @stdout.puts "  Project: .claude/memory.sqlite3 (project-specific)"
      @stdout.puts "\nNext steps:"
      @stdout.puts "  1. Restart Claude Code to load the new configuration"
      @stdout.puts "  2. Use Claude Code normally - transcripts will be ingested automatically"
      @stdout.puts "  3. Run 'claude-memory promote <fact_id>' to move facts to global"
      @stdout.puts "  4. Run 'claude-memory doctor' to verify setup"

      0
    end

    def init_global
      @stdout.puts "Initializing ClaudeMemory (global only)...\n\n"

      manager = ClaudeMemory::Store::StoreManager.new
      manager.ensure_global!
      @stdout.puts "✓ Created global database: #{manager.global_db_path}"
      manager.close

      configure_global_hooks
      configure_global_mcp
      configure_global_memory

      @stdout.puts "\n=== Global Setup Complete ===\n"
      @stdout.puts "ClaudeMemory is now configured globally."
      @stdout.puts "\nNote: Run 'claude-memory init' in each project for project-specific memory."

      0
    end

    def configure_global_hooks
      settings_path = File.join(Dir.home, ".claude", "settings.json")
      db_path = ClaudeMemory.global_db_path

      ingest_cmd = "claude-memory hook ingest --db #{db_path}"
      sweep_cmd = "claude-memory hook sweep --db #{db_path}"

      hooks_config = build_hooks_config(ingest_cmd, sweep_cmd)

      existing = load_json_file(settings_path)
      existing["hooks"] ||= {}
      existing["hooks"].merge!(hooks_config["hooks"])

      File.write(settings_path, JSON.pretty_generate(existing))
      @stdout.puts "✓ Configured hooks in #{settings_path}"
    end

    def configure_global_mcp
      mcp_path = File.join(Dir.home, ".claude.json")

      existing = load_json_file(mcp_path)
      existing["mcpServers"] ||= {}
      existing["mcpServers"]["claude-memory"] = {
        "type" => "stdio",
        "command" => "claude-memory",
        "args" => ["serve-mcp"]
      }

      File.write(mcp_path, JSON.pretty_generate(existing))
      @stdout.puts "✓ Configured MCP server in #{mcp_path}"
    end

    def configure_global_memory
      global_claude_dir = File.join(Dir.home, ".claude")
      claude_md_path = File.join(global_claude_dir, "CLAUDE.md")

      memory_instruction = <<~MD
        # ClaudeMemory

        ClaudeMemory is installed globally. Use these MCP tools:
        - `memory.recall` - Search for relevant facts
        - `memory.explain` - Get detailed fact provenance
        - `memory.conflicts` - Show open contradictions
        - `memory.status` - Check system health
      MD

      if File.exist?(claude_md_path)
        content = File.read(claude_md_path)
        if content.include?("ClaudeMemory")
          @stdout.puts "✓ #{claude_md_path} already has ClaudeMemory instructions"
        else
          File.write(claude_md_path, content + "\n" + memory_instruction)
          @stdout.puts "✓ Added ClaudeMemory instructions to #{claude_md_path}"
        end
      else
        File.write(claude_md_path, memory_instruction)
        @stdout.puts "✓ Created #{claude_md_path}"
      end
    end

    def configure_project_hooks
      hooks_path = ".claude/settings.json"
      db_path = File.expand_path(ClaudeMemory.project_db_path)

      ingest_cmd = "claude-memory hook ingest --db #{db_path}"
      sweep_cmd = "claude-memory hook sweep --db #{db_path}"

      hooks_config = build_hooks_config(ingest_cmd, sweep_cmd)

      existing = load_json_file(hooks_path)
      existing["hooks"] ||= {}
      existing["hooks"].merge!(hooks_config["hooks"])

      FileUtils.mkdir_p(".claude")
      File.write(hooks_path, JSON.pretty_generate(existing))
      @stdout.puts "✓ Configured hooks in #{hooks_path}"
    end

    def configure_project_mcp
      mcp_path = ".mcp.json"

      existing = load_json_file(mcp_path)
      existing["mcpServers"] ||= {}
      existing["mcpServers"]["claude-memory"] = {
        "type" => "stdio",
        "command" => "claude-memory",
        "args" => ["serve-mcp"]
      }

      File.write(mcp_path, JSON.pretty_generate(existing))
      @stdout.puts "✓ Configured MCP server in #{mcp_path}"
    end

    def install_output_style
      templates_dir = File.expand_path("templates", __dir__)
      style_source = File.join(templates_dir, "output-styles", "memory-aware.md")
      style_dest = ".claude/output-styles/memory-aware.md"

      FileUtils.mkdir_p(File.dirname(style_dest))
      FileUtils.cp(style_source, style_dest)
      @stdout.puts "✓ Installed output style at #{style_dest}"
    end

    def doctor_cmd
      issues = []
      warnings = []

      @stdout.puts "Claude Memory Doctor\n"
      @stdout.puts "=" * 40

      manager = ClaudeMemory::Store::StoreManager.new

      @stdout.puts "\n## Global Database"
      check_database(manager.global_db_path, "global", issues, warnings)

      @stdout.puts "\n## Project Database"
      check_database(manager.project_db_path, "project", issues, warnings)

      manager.close

      if File.exist?(".claude/rules/claude_memory.generated.md")
        @stdout.puts "✓ Published snapshot exists"
      else
        warnings << "No published snapshot found. Run 'claude-memory publish'"
      end

      if File.exist?(".claude/CLAUDE.md")
        content = File.read(".claude/CLAUDE.md")
        if content.include?("claude_memory.generated.md")
          @stdout.puts "✓ CLAUDE.md imports snapshot"
        else
          warnings << "CLAUDE.md does not import snapshot"
        end
      else
        warnings << "No .claude/CLAUDE.md found"
      end

      check_hooks_config(warnings)

      @stdout.puts

      if warnings.any?
        @stdout.puts "Warnings:"
        warnings.each { |w| @stdout.puts "  ⚠ #{w}" }
        @stdout.puts
      end

      if issues.any?
        @stdout.puts "Issues:"
        issues.each { |i| @stderr.puts "  ✗ #{i}" }
        @stdout.puts
        @stdout.puts "Run 'claude-memory init' to set up."
        return 1
      end

      @stdout.puts "All checks passed!"
      0
    end

    def check_database(db_path, label, issues, warnings)
      if File.exist?(db_path)
        @stdout.puts "✓ #{label.capitalize} database exists: #{db_path}"
        begin
          store = ClaudeMemory::Store::SQLiteStore.new(db_path)
          @stdout.puts "  Schema version: #{store.schema_version}"

          fact_count = store.db.execute("SELECT COUNT(*) FROM facts").first.first
          @stdout.puts "  Facts: #{fact_count}"

          content_count = store.db.execute("SELECT COUNT(*) FROM content_items").first.first
          @stdout.puts "  Content items: #{content_count}"

          conflict_count = store.db.execute("SELECT COUNT(*) FROM conflicts WHERE status = 'open'").first.first
          if conflict_count > 0
            warnings << "#{label}: #{conflict_count} open conflict(s) need resolution"
          end
          @stdout.puts "  Open conflicts: #{conflict_count}"

          last_ingest = store.db.execute("SELECT MAX(ingested_at) FROM content_items").first.first
          if last_ingest
            @stdout.puts "  Last ingest: #{last_ingest}"
          elsif label == "project"
            warnings << "#{label}: No content has been ingested yet"
          end

          store.close
        rescue => e
          issues << "#{label} database error: #{e.message}"
        end
      elsif label == "global"
        issues << "Global database not found: #{db_path}"
      else
        warnings << "Project database not found: #{db_path} (run 'claude-memory init')"
      end
    end

    def check_hooks_config(warnings)
      settings_path = ".claude/settings.json"
      local_settings_path = ".claude/settings.local.json"

      hooks_found = false

      [settings_path, local_settings_path].each do |path|
        next unless File.exist?(path)

        begin
          config = JSON.parse(File.read(path))
          if config["hooks"]&.any?
            hooks_found = true
            @stdout.puts "✓ Hooks configured in #{path}"

            expected_hooks = %w[Stop SessionStart PreCompact SessionEnd]
            missing = expected_hooks - config["hooks"].keys
            if missing.any?
              warnings << "Missing recommended hooks in #{path}: #{missing.join(", ")}"
            end
          end
        rescue JSON::ParserError
          warnings << "Invalid JSON in #{path}"
        end
      end

      unless hooks_found
        warnings << "No hooks configured. Run 'claude-memory init' or configure manually."
        @stdout.puts "\n  Manual fallback available:"
        @stdout.puts "    claude-memory ingest --session-id <id> --transcript-path <path>"
        @stdout.puts "    claude-memory sweep --budget 5"
        @stdout.puts "    claude-memory publish"
      end
    end

    def load_json_file(path)
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def build_hooks_config(ingest_cmd, sweep_cmd)
      {
        "hooks" => {
          "Stop" => [
            {
              "matcher" => "",
              "hooks" => [
                {"type" => "command", "command" => ingest_cmd, "timeout" => 10}
              ]
            }
          ],
          "SessionStart" => [
            {
              "matcher" => "",
              "hooks" => [
                {"type" => "command", "command" => ingest_cmd, "timeout" => 10}
              ]
            }
          ],
          "PreCompact" => [
            {
              "matcher" => "",
              "hooks" => [
                {"type" => "command", "command" => ingest_cmd, "timeout" => 30},
                {"type" => "command", "command" => sweep_cmd, "timeout" => 30}
              ]
            }
          ],
          "SessionEnd" => [
            {
              "matcher" => "",
              "hooks" => [
                {"type" => "command", "command" => ingest_cmd, "timeout" => 30},
                {"type" => "command", "command" => sweep_cmd, "timeout" => 30}
              ]
            }
          ]
        }
      }
    end
  end
end
