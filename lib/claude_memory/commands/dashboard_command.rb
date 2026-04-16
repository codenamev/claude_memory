# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Starts a local web dashboard for debugging and observability.
    # Shows stats, activity timeline, fact explorer, and efficacy reports.
    class DashboardCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {port: Dashboard::Server::DEFAULT_PORT, no_open: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory dashboard [options]"
            parser.on("--port PORT", Integer, "Server port (default: #{Dashboard::Server::DEFAULT_PORT})") { |v| o[:port] = v }
            parser.on("--no-open", "Don't auto-open browser") { o[:no_open] = true }
          end
        end
        return 1 if opts.nil?

        manager = Store::StoreManager.new

        unless manager.global_exists? || manager.project_exists?
          stderr.puts "No memory databases found. Run 'claude-memory init' first."
          manager.close
          return 1
        end

        manager.ensure_both! if manager.global_exists? && manager.project_exists?
        manager.ensure_global! if manager.global_exists?
        manager.ensure_project! if manager.project_exists?

        stdout.puts "Starting ClaudeMemory dashboard on http://localhost:#{opts[:port]}"
        stdout.puts "Press Ctrl+C to stop."

        server = Dashboard::Server.new(
          manager: manager,
          port: opts[:port],
          open_browser: !opts[:no_open]
        )

        server.start
        manager.close
        0
      end
    end
  end
end
