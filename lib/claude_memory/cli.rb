# frozen_string_literal: true

module ClaudeMemory
  # Thin command router - dispatches to command classes via Registry
  class CLI
    def initialize(args = ARGV, stdout: $stdout, stderr: $stderr, stdin: $stdin)
      @args = args
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
    end

    def run
      command_name = @args.first || "help"
      command_name = normalize_command(command_name)

      command_class = Commands::Registry.find(command_name)
      unless command_class
        @stderr.puts "Unknown command: #{command_name}"
        @stderr.puts "Run 'claude-memory help' for usage."
        return 1
      end

      command = command_class.new(stdout: @stdout, stderr: @stderr, stdin: @stdin)
      command.call(@args[1..-1] || [])
    end

    private

    def normalize_command(cmd)
      case cmd
      when "-h", "--help"
        "help"
      when "-v", "--version"
        "version"
      else
        cmd
      end
    end
  end
end
