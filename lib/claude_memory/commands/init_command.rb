# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Initializes ClaudeMemory in a project or globally
    # Delegates to specialized initializer classes for actual setup
    class InitCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {global: false}) do |o|
          OptionParser.new do |parser|
            parser.on("--global", "Install to global ~/.claude/ settings") { o[:global] = true }
          end
        end
        return 1 if opts.nil?

        initializer = if opts[:global]
          Initializers::GlobalInitializer.new(stdout, stderr, stdin)
        else
          Initializers::ProjectInitializer.new(stdout, stderr, stdin)
        end

        initializer.initialize_memory
      end
    end
  end
end
