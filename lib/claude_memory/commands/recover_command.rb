# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Recovers from stuck operations by resetting them
    class RecoverCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {operation: nil, scope: nil}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory recover [options]"
            parser.on("--operation TYPE", "Filter by operation type") { |v| o[:operation] = v }
            parser.on("--scope SCOPE", "Filter by scope (global/project)") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = Store::StoreManager.new

        total_reset = 0

        # Reset stuck operations in global database
        if opts[:scope].nil? || opts[:scope] == "global"
          if File.exist?(manager.global_db_path)
            count = reset_stuck_operations(
              manager.global_store,
              "global",
              opts[:operation]
            )
            total_reset += count
          end
        end

        # Reset stuck operations in project database
        if opts[:scope].nil? || opts[:scope] == "project"
          if File.exist?(manager.project_db_path)
            count = reset_stuck_operations(
              manager.project_store,
              "project",
              opts[:operation]
            )
            total_reset += count
          end
        end

        manager.close

        if total_reset.zero?
          stdout.puts "No stuck operations found."
        else
          stdout.puts "Reset #{total_reset} stuck operation(s)."
          stdout.puts "You can now re-run the failed operation."
        end

        0
      end

      private

      def reset_stuck_operations(store, scope_label, operation_type_filter)
        tracker = Infrastructure::OperationTracker.new(store)

        count = tracker.reset_stuck_operations(
          operation_type: operation_type_filter,
          scope: scope_label
        )

        if count > 0
          stdout.puts "#{scope_label.capitalize}: Reset #{count} stuck operation(s)"
        end

        count
      end
    end
  end
end
