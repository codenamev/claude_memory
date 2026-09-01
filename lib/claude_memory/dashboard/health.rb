# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Dashboard
    # Aggregates the dashboard "/health" report from four checks: per-database
    # schema/fact health (global + project), claude-code hooks installation,
    # and the sqlite-vec vector index. Each check returns a {name, status,
    # message, fix?} hash; the report's overall status escalates to the
    # worst individual status (error > warning > healthy).
    #
    # Pulled out of Dashboard::API so the wiring lives next to the data
    # rather than next to the HTTP routing.
    class Health
      HOOKS_SETTINGS_PATHS = [".claude/settings.json", ".claude/settings.local.json"].freeze
      VEC_LOW_COVERAGE_PCT = 10
      VEC_WARN_COVERAGE_PCT = 50

      def initialize(manager)
        @manager = manager
      end

      def report
        checks = [
          db_check("global", @manager.global_db_path),
          db_check("project", @manager.project_db_path),
          hooks_check,
          vec_check
        ]
        {status: aggregate_status(checks), checks: checks, version: ClaudeMemory::VERSION}
      end

      private

      def aggregate_status(checks)
        return "error" if checks.any? { |c| c[:status] == "error" }
        return "warning" if checks.any? { |c| c[:status] == "warning" }
        "healthy"
      end

      def db_check(label, path)
        unless File.exist?(path)
          return {
            name: "#{label}_database",
            status: "warning",
            message: "Not initialized",
            fix: "Run `claude-memory init` to create the #{label} database at #{path}."
          }
        end

        store = @manager.store_for_scope(label)
        version = store.schema_version
        expiring = store.facts.where(status: "expiring").count
        message = "Schema v#{version}, #{store.facts.where(status: "active").count} active facts"
        message += ", #{expiring} expiring (awaiting ratification)" if expiring.positive?
        {
          name: "#{label}_database",
          status: "healthy",
          message: message
        }
      rescue => e
        {
          name: "#{label}_database",
          status: "error",
          message: e.message,
          fix: "Inspect the error above. Common causes: corrupt schema, file permissions, or a stale lock. Try `claude-memory recover --scope #{label}`, or remove the file at #{path} and re-run `claude-memory init`."
        }
      end

      def hooks_check
        present = collect_configured_hook_types
        expected = Commands::Checks::HooksCheck::EXPECTED_HOOKS
        missing = expected - present

        if present.empty?
          return {
            name: "hooks",
            status: "error",
            message: "No claude-memory hooks found in #{HOOKS_SETTINGS_PATHS.join(" or ")}",
            fix: "Run `claude-memory init` to install the standard hook set (#{expected.join(", ")})."
          }
        end

        return {name: "hooks", status: "healthy", message: "All #{expected.size} hooks configured"} if missing.empty?

        {
          name: "hooks",
          status: "warning",
          message: "#{present.size}/#{expected.size} hooks configured",
          fix: "Missing hook(s): #{missing.join(", ")}. Run `claude-memory init` to install the standard set, or add them manually under `hooks.<EventName>[].hooks[]` in .claude/settings.json."
        }
      rescue => e
        {
          name: "hooks",
          status: "error",
          message: e.message,
          fix: "Failed to read hook settings. Verify .claude/settings.json is valid JSON, then re-run `claude-memory doctor`."
        }
      end

      # Walks the two-level hook structure Claude Code uses:
      # hooks.<EventName>[] -> matcher hash -> .hooks[] -> { type:, command: }
      def collect_configured_hook_types
        types = []
        HOOKS_SETTINGS_PATHS.each do |relpath|
          path = File.join(Dir.pwd, relpath)
          next unless File.exist?(path)

          settings = JSON.parse(File.read(path))
          hooks = settings["hooks"] || {}
          hooks.each do |event_type, matchers|
            next unless matchers.is_a?(Array)
            has_claude_memory = matchers.any? do |matcher|
              next false unless matcher.is_a?(Hash) && matcher["hooks"].is_a?(Array)
              matcher["hooks"].any? { |h| h.is_a?(Hash) && h["command"]&.include?("claude-memory") }
            end
            types << event_type if has_claude_memory
          end
        end
        types.uniq
      end

      def vec_check
        store = @manager.default_store(prefer: :project)
        unless store
          return {
            name: "vectors",
            status: "warning",
            message: "No database",
            fix: "Initialize a database first with `claude-memory init`."
          }
        end

        vec = store.vector_index
        return vec_unavailable_check unless vec.available?

        vec_coverage_check(vec)
      rescue => e
        {
          name: "vectors",
          status: "warning",
          message: e.message,
          fix: "Vector index threw an error. Try `claude-memory index --vec --rebuild` to rebuild from facts."
        }
      end

      def vec_unavailable_check
        {
          name: "vectors",
          status: "warning",
          message: "sqlite-vec not available",
          fix: "The sqlite-vec extension didn't load. Run `bundle install` to install the gem (>= 0.1.9). Semantic recall will be disabled until this is fixed; lexical recall still works."
        }
      end

      def vec_coverage_check(vec)
        coverage = vec.coverage_stats
        indexed = coverage[:vec_indexed] || 0
        total = coverage[:with_embedding] || 0
        pct = coverage[:coverage_pct] || 0
        message = (total > 0) ? "#{indexed}/#{total} facts indexed (#{pct}%)" : "0 facts have embeddings yet"

        status = vec_status_for(total, pct)
        result = {name: "vectors", status: status, message: message}
        result[:fix] = "Vector coverage is low — run `claude-memory index --vec --rebuild` to regenerate embeddings and reindex all active facts. Semantic recall accuracy degrades as this drops." unless status == "healthy"
        result
      end

      def vec_status_for(total, pct)
        return "healthy" if total.zero?
        return "error" if pct < VEC_LOW_COVERAGE_PCT
        return "warning" if pct < VEC_WARN_COVERAGE_PCT
        "healthy"
      end
    end
  end
end
