# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Performs system health checks for ClaudeMemory
    # Delegates to specialized check classes for actual validation
    class DoctorCommand < BaseCommand
      def call(_args)
        manager = ClaudeMemory::Store::StoreManager.new

        checks = [
          Checks::DatabaseCheck.new(manager.global_db_path, "global"),
          Checks::DatabaseCheck.new(manager.project_db_path, "project"),
          Checks::SnapshotCheck.new,
          Checks::ClaudeMdCheck.new,
          Checks::HooksCheck.new
        ]

        results = checks.map(&:call)

        manager.close

        reporter = Checks::Reporter.new(stdout, stderr)
        success = reporter.report(results)

        success ? 0 : 1
      end
    end
  end
end
