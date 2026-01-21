# frozen_string_literal: true

require "optparse"

module ClaudeMemory
  module Commands
    # Base class for all CLI commands.
    # Provides consistent interface for commands with I/O isolation for testing.
    #
    # @example Implementing a command
    #   class MyCommand < BaseCommand
    #     def call(args)
    #       opts = parse_options(args, {verbose: false}) do |o|
    #         OptionParser.new do |parser|
    #           parser.on("-v", "--verbose") { o[:verbose] = true }
    #         end
    #       end
    #       return 1 if opts.nil?
    #
    #       # ... command logic ...
    #       success("Done!")
    #     end
    #   end
    #
    # @example Testing a command
    #   stdout = StringIO.new
    #   stderr = StringIO.new
    #   command = MyCommand.new(stdout: stdout, stderr: stderr)
    #   exit_code = command.call(["--verbose"])
    #   expect(exit_code).to eq(0)
    #   expect(stdout.string).to include("Done!")
    class BaseCommand
      attr_reader :stdout, :stderr, :stdin

      # @param stdout [IO] output stream (default: $stdout)
      # @param stderr [IO] error stream (default: $stderr)
      # @param stdin [IO] input stream (default: $stdin)
      def initialize(stdout: $stdout, stderr: $stderr, stdin: $stdin)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
      end

      # Execute the command with given arguments
      # @param args [Array<String>] command line arguments
      # @return [Integer] exit code (0 for success, non-zero for failure)
      def call(args)
        raise NotImplementedError, "Subclass must implement #call"
      end

      protected

      # Report successful command execution
      # @param message [String, nil] optional success message
      # @param exit_code [Integer] exit code (default: 0)
      # @return [Integer] the exit code
      def success(message = nil, exit_code: 0)
        stdout.puts(message) if message
        exit_code
      end

      # Report failed command execution
      # @param message [String] error message
      # @param exit_code [Integer] exit code (default: 1)
      # @return [Integer] the exit code
      def failure(message, exit_code: 1)
        stderr.puts(message)
        exit_code
      end

      # Parse command line options with error handling
      # @param args [Array<String>] command line arguments
      # @param defaults [Hash] default option values
      # @yield [Hash] yields the options hash to configure the parser
      # @return [Hash, nil] parsed options, or nil if parsing failed
      #
      # @example
      #   opts = parse_options(args, {verbose: false}) do |o|
      #     OptionParser.new do |parser|
      #       parser.on("-v", "--verbose") { o[:verbose] = true }
      #       parser.on("--name NAME") { |v| o[:name] = v }
      #     end
      #   end
      def parse_options(args, defaults = {})
        opts = defaults.dup
        parser = yield(opts)
        parser.parse(args)
        opts
      rescue OptionParser::InvalidOption => e
        failure(e.message)
        nil
      end
    end
  end
end
