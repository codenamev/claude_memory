# frozen_string_literal: true

RSpec.describe ClaudeMemory::Commands::CompletionCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  describe "zsh completion" do
    it "generates zsh completion script" do
      exit_code = command.call(["--shell", "zsh"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("#compdef claude-memory")
      expect(stdout.string).to include("_claude_memory")
    end

    it "includes all registered commands" do
      command.call(["--shell", "zsh"])
      ClaudeMemory::Commands::Registry.all_commands.each do |cmd|
        expect(stdout.string).to include(cmd)
      end
    end

    it "includes hook subcommands" do
      command.call(["--shell", "zsh"])
      expect(stdout.string).to include("ingest")
      expect(stdout.string).to include("sweep")
      expect(stdout.string).to include("publish")
    end
  end

  describe "bash completion" do
    it "generates bash completion script" do
      exit_code = command.call(["--shell", "bash"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("complete -F _claude_memory claude-memory")
    end

    it "includes all registered commands" do
      command.call(["--shell", "bash"])
      ClaudeMemory::Commands::Registry.all_commands.each do |cmd|
        expect(stdout.string).to include(cmd)
      end
    end
  end

  describe "auto-detection" do
    it "detects zsh from SHELL env" do
      allow(ENV).to receive(:fetch).with("SHELL", "/bin/bash").and_return("/bin/zsh")
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("#compdef")
    end

    it "defaults to bash" do
      allow(ENV).to receive(:fetch).with("SHELL", "/bin/bash").and_return("/bin/bash")
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("complete -F")
    end
  end
end
