# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Performs system health checks for ClaudeMemory
    # Delegates to specialized check classes for actual validation
    class DoctorCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {brief: false}) do |o|
          OptionParser.new do |parser|
            parser.on("--brief", "Output single-line status summary") { o[:brief] = true }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new

        checks = [
          Checks::DatabaseCheck.new(manager.global_db_path, "global"),
          Checks::DatabaseCheck.new(manager.project_db_path, "project"),
          Checks::DistillCheck.new(manager.global_db_path, "global"),
          Checks::DistillCheck.new(manager.project_db_path, "project"),
          Checks::VecCheck.new,
          Checks::SnapshotCheck.new,
          Checks::ClaudeMdCheck.new,
          Checks::HooksCheck.new
        ]

        results = checks.map(&:call)

        manager.close

        if opts[:brief]
          report_brief(results)
        else
          reporter = Checks::Reporter.new(stdout, stderr)
          success = reporter.report(results)
          success ? 0 : 1
        end
      end

      private

      def report_brief(results)
        errors = results.select { |r| r[:status] == :error }
        warnings = results.select { |r| r[:status] == :warning }

        if errors.any?
          messages = errors.map { |e| e[:message] }
          stdout.puts "Memory ERROR: #{messages.join(", ")}"
          return 1
        end

        fact_parts = results
          .select { |r| r[:label] =~ /global|project/ && r.dig(:details, :fact_count) }
          .map { |r| "#{r.dig(:details, :fact_count)} facts (#{r[:label]})" }

        status = warnings.any? ? "WARNING" : "OK"
        summary = fact_parts.any? ? fact_parts.join(", ") : "no databases"

        if warnings.any?
          warning_msgs = warnings.map { |w| w[:message] }.join("; ")
          stdout.puts "Memory #{status}: #{summary} [#{warning_msgs}]"
        else
          stdout.puts "Memory #{status}: #{summary}"
        end

        0
      end
    end
  end
end
