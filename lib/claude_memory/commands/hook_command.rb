# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Commands
    # Handles hook entrypoints (ingest, sweep, publish)
    # Supports --async flag to fork and run in background
    class HookCommand < BaseCommand
      ASYNC_SUBCOMMANDS = %w[ingest sweep publish].freeze

      def call(args)
        subcommand = args.first

        unless subcommand
          stderr.puts "Usage: claude-memory hook <ingest|sweep|publish|context> [options]"
          stderr.puts "\nReads hook payload JSON from stdin."
          stderr.puts "Options: --async  Run in background (ingest, sweep, publish only)"
          return Hook::ExitCodes::ERROR
        end

        unless %w[ingest sweep publish context nudge].include?(subcommand)
          stderr.puts "Unknown hook command: #{subcommand}"
          stderr.puts "Available: ingest, sweep, publish, context, nudge"
          return Hook::ExitCodes::ERROR
        end

        opts = parse_options(args[1..] || [], {db: ClaudeMemory.project_db_path, async: false}) do |o|
          OptionParser.new do |parser|
            parser.on("--db PATH", "Database path") { |v| o[:db] = v }
            parser.on("--async", "Run in background (non-blocking)") { o[:async] = true }
          end
        end
        return Hook::ExitCodes::ERROR if opts.nil?

        payload = parse_hook_payload
        return Hook::ExitCodes::ERROR unless payload

        if opts[:async] && ASYNC_SUBCOMMANDS.include?(subcommand)
          return run_async(subcommand, payload, opts)
        end

        execute_sync(subcommand, payload, opts)
      rescue ClaudeMemory::Hook::Handler::PayloadError => e
        stderr.puts "Payload error: #{e.message}"
        Hook::ExitCodes::ERROR
      rescue => e
        classify_error(e)
      end

      private

      def execute_sync(subcommand, payload, opts)
        store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
        handler = ClaudeMemory::Hook::Handler.new(store)

        exit_code = case subcommand
        when "ingest"
          hook_ingest(handler, payload)
        when "sweep"
          hook_sweep(handler, payload)
        when "publish"
          hook_publish(handler, payload)
        when "context"
          hook_context(payload, opts[:db])
        when "nudge"
          hook_nudge(payload, opts[:db])
        end

        store.close
        exit_code
      end

      def run_async(subcommand, payload, opts)
        pid = fork_background(subcommand, payload, opts)

        if pid
          Process.detach(pid)
          stdout.puts "Running #{subcommand} in background (pid: #{pid})"
          Hook::ExitCodes::SUCCESS
        else
          stderr.puts "Fork not available, falling back to synchronous execution"
          execute_sync(subcommand, payload, opts)
        end
      end

      def fork_background(subcommand, payload, opts)
        Process.fork do
          # Detach from parent I/O
          $stdin.reopen(File::NULL, "r")
          $stdout.reopen(File::NULL, "w")
          $stderr.reopen(File::NULL, "w")

          store = ClaudeMemory::Store::SQLiteStore.new(opts[:db])
          handler = ClaudeMemory::Hook::Handler.new(store)

          case subcommand
          when "ingest" then handler.ingest(payload)
          when "sweep" then handler.sweep(payload)
          when "publish" then handler.publish(payload)
          end

          store.close
        rescue
          # Background process must not propagate errors
          nil
        end
      rescue NotImplementedError
        # Process.fork not available (e.g., JRuby)
        nil
      end

      def parse_hook_payload
        input = stdin.read
        JSON.parse(input)
      rescue JSON::ParserError => e
        stderr.puts "Invalid JSON payload: #{e.message}"
        nil
      end

      def hook_ingest(handler, payload)
        result = handler.ingest(payload)

        case result[:status]
        when :ingested
          stdout.puts "Ingested #{result[:bytes_read]} bytes (content_id: #{result[:content_id]})"
          Hook::ExitCodes::SUCCESS
        when :no_change
          stdout.puts "No new content to ingest"
          Hook::ExitCodes::SUCCESS
        when :skipped
          # Different reasons for skipping have different severity
          case result[:reason]
          when "unchanged"
            stdout.puts "No new content to ingest"
            Hook::ExitCodes::SUCCESS
          when "session_excluded"
            stdout.puts "Session excluded by privacy marker"
            Hook::ExitCodes::SUCCESS
          else
            # transcript_not_found or other skipped reasons
            stdout.puts "Skipped ingestion: #{result[:reason]}"
            Hook::ExitCodes::WARNING
          end
        else
          Hook::ExitCodes::ERROR
        end
      end

      def hook_sweep(handler, payload)
        result = handler.sweep(payload)
        stats = result[:stats]

        stdout.puts "Sweep complete:"
        stdout.puts "  Elapsed: #{stats[:elapsed_seconds].round(2)}s"
        stdout.puts "  Budget honored: #{stats[:budget_honored]}"

        Hook::ExitCodes::SUCCESS
      end

      def hook_publish(handler, payload)
        result = handler.publish(payload)

        case result[:status]
        when :updated
          stdout.puts "Published snapshot to #{result[:path]}"
        when :unchanged
          stdout.puts "No changes - #{result[:path]} is up to date"
        end

        Hook::ExitCodes::SUCCESS
      end

      def hook_nudge(payload, db_path)
        # Nudge needs to count past nudge events across both stores,
        # so prefer the manager-aware path. db_path overrides only
        # the project store (useful for tests).
        project_path = payload["project_path"] || payload["cwd"]
        manager = ClaudeMemory::Store::StoreManager.new(
          project_db_path: db_path, project_path: project_path
        )
        manager.ensure_both!
        store = manager.project_store || manager.global_store

        handler = ClaudeMemory::Hook::Handler.new(store, manager: manager)
        result = handler.nudge(payload)

        stdout.puts result[:message] if result[:status] == :emitted

        manager.close
        Hook::ExitCodes::SUCCESS
      rescue => e
        classify_error(e)
      end

      def hook_context(payload, db_path)
        project_path = payload["project_path"] || payload["cwd"]
        source = payload["source"]
        session_id = payload["session_id"]
        manager = ClaudeMemory::Store::StoreManager.new(
          project_db_path: db_path,
          project_path: project_path
        )
        manager.ensure_both!

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        injector = ClaudeMemory::Hook::ContextInjector.new(manager, source: source)
        context_text = injector.generate_context
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        if context_text
          response = {
            hookSpecificOutput: {
              hookEventName: "SessionStart",
              additionalContext: context_text
            }
          }
          stdout.puts JSON.generate(response)
        end

        record_context_activity(manager, context_text, injector,
          session_id: session_id, source: source, duration_ms: duration_ms)

        manager.close
        Hook::ExitCodes::SUCCESS
      rescue => e
        classify_error(e)
      end

      CONTEXT_PREVIEW_BYTES = 400

      def record_context_activity(manager, context_text, injector, session_id:, source:, duration_ms:)
        store = manager.project_store || manager.global_store
        return unless store

        by_scope = injector.emitted_facts_by_scope.transform_values { |ids| ids.first(10) }
        details = {
          source: source,
          context_length: context_text&.length,
          context_tokens: ClaudeMemory::Core::TokenEstimator.estimate(context_text),
          preview: context_text&.byteslice(0, CONTEXT_PREVIEW_BYTES),
          truncated: context_text ? context_text.bytesize > CONTEXT_PREVIEW_BYTES : false,
          top_fact_ids: injector.emitted_fact_ids.first(10),
          top_facts_by_scope: (by_scope if by_scope.any?),
          top_subjects: injector.emitted_subjects.uniq.first(10),
          fact_count: injector.emitted_fact_ids.size,
          observation_count: injector.emitted_observation_count
        }.compact

        ClaudeMemory::ActivityLog.record(store,
          event_type: "hook_context",
          status: context_text ? "success" : "skipped",
          session_id: session_id,
          duration_ms: duration_ms,
          details: details)
      rescue => e
        ClaudeMemory.logger.debug("record_context_activity failed: #{e.message}")
      end

      def classify_error(error)
        exit_code = Hook::ErrorClassifier.exit_code_for(error)

        if exit_code == Hook::ExitCodes::SUCCESS
          # Transport/infrastructure error — degrade gracefully
          stderr.puts "Hook degraded gracefully: #{error.class} - #{error.message}"
        else
          # Client/programming error — surface to developer
          stderr.puts "Hook error: #{error.class} - #{error.message}"
        end

        exit_code
      end
    end
  end
end
