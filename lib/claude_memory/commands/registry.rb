# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Registry for CLI command lookup and dispatch
    # Maps command names to command classes for dynamic dispatch
    class Registry
      # Map of command names to class names
      # As more commands are extracted, add them here
      COMMANDS = {
        "help" => "HelpCommand",
        "version" => "VersionCommand",
        "doctor" => "DoctorCommand",
        "promote" => "PromoteCommand",
        "search" => "SearchCommand",
        "explain" => "ExplainCommand",
        "conflicts" => "ConflictsCommand",
        "changes" => "ChangesCommand",
        "recall" => "RecallCommand",
        "sweep" => "SweepCommand"
        # More commands will be added as they're extracted:
        # "ingest" => "IngestCommand",
        # "publish" => "PublishCommand",
        # "sweep" => "SweepCommand",
        # "conflicts" => "ConflictsCommand",
        # "changes" => "ChangesCommand",
        # "db:init" => "DbInitCommand",
        # "init" => "InitCommand",
        # "serve-mcp" => "ServeMcpCommand",
        # "hook" => "HookCommand"
      }.freeze

      # Find a command class by name
      # @param command_name [String] the command name (e.g., "help", "version")
      # @return [Class, nil] the command class, or nil if not found
      def self.find(command_name)
        return nil if command_name.nil?

        class_name = COMMANDS[command_name]
        return nil unless class_name

        Commands.const_get(class_name)
      end

      # Get all registered command names
      # @return [Array<String>] list of command names
      def self.all_commands
        COMMANDS.keys
      end

      # Check if a command is registered
      # @param command_name [String] the command name
      # @return [Boolean] true if registered
      def self.registered?(command_name)
        COMMANDS.key?(command_name)
      end
    end
  end
end
