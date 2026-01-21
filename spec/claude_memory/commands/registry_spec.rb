# frozen_string_literal: true

RSpec.describe ClaudeMemory::Commands::Registry do
  describe ".find" do
    it "returns HelpCommand for 'help'" do
      command_class = described_class.find("help")
      expect(command_class).to eq(ClaudeMemory::Commands::HelpCommand)
    end

    it "returns VersionCommand for 'version'" do
      command_class = described_class.find("version")
      expect(command_class).to eq(ClaudeMemory::Commands::VersionCommand)
    end

    it "returns DoctorCommand for 'doctor'" do
      command_class = described_class.find("doctor")
      expect(command_class).to eq(ClaudeMemory::Commands::DoctorCommand)
    end

    it "returns nil for unknown command" do
      command_class = described_class.find("unknown")
      expect(command_class).to be_nil
    end

    it "returns nil for nil command" do
      command_class = described_class.find(nil)
      expect(command_class).to be_nil
    end
  end

  describe ".all_commands" do
    it "returns array of command names" do
      commands = described_class.all_commands
      expect(commands).to be_an(Array)
      expect(commands).to include("help")
      expect(commands).to include("version")
      expect(commands).to include("doctor")
    end

    it "includes all registered commands" do
      commands = described_class.all_commands
      # At minimum, should have the 3 we've extracted
      expect(commands.size).to be >= 3
    end
  end

  describe ".registered?" do
    it "returns true for registered command" do
      expect(described_class.registered?("help")).to be true
    end

    it "returns false for unregistered command" do
      expect(described_class.registered?("nonexistent")).to be false
    end
  end
end
