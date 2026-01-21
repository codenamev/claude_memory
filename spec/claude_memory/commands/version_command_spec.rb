# frozen_string_literal: true

require "stringio"

RSpec.describe ClaudeMemory::Commands::VersionCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  describe "#call" do
    it "prints version to stdout" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("claude-memory")
      expect(stdout.string).to include(ClaudeMemory::VERSION)
    end

    it "writes nothing to stderr" do
      command.call([])
      expect(stderr.string).to be_empty
    end

    it "returns exit code 0" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
    end

    it "ignores any arguments passed" do
      exit_code = command.call(["--foo", "bar"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include(ClaudeMemory::VERSION)
    end

    it "outputs format 'claude-memory VERSION'" do
      command.call([])
      expect(stdout.string.strip).to match(/^claude-memory \d+\.\d+\.\d+/)
    end
  end
end
