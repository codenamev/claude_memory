# frozen_string_literal: true

require "stringio"

RSpec.describe ClaudeMemory::Commands::BaseCommand do
  # Concrete test command for testing base functionality
  class TestCommand < ClaudeMemory::Commands::BaseCommand
    def call(args)
      if args.include?("--fail")
        failure("Test failed", exit_code: 2)
      elsif args.include?("--success")
        success("Test succeeded", exit_code: 0)
      elsif args.include?("--no-message")
        success
      else
        opts = parse_options(args, {name: "default"}) do |o|
          OptionParser.new do |parser|
            parser.on("--name NAME", "Name parameter") do |v|
              o[:name] = v
            end
          end
        end
        return 1 if opts.nil? # parse_options returns nil on error
        success("Hello #{opts[:name]}")
      end
    end
  end

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:stdin) { StringIO.new }
  let(:command) { TestCommand.new(stdout: stdout, stderr: stderr, stdin: stdin) }

  describe "#initialize" do
    it "accepts custom stdout, stderr, stdin" do
      expect(command.stdout).to eq(stdout)
      expect(command.stderr).to eq(stderr)
      expect(command.stdin).to eq(stdin)
    end

    it "defaults to standard streams" do
      cmd = TestCommand.new
      expect(cmd.stdout).to eq($stdout)
      expect(cmd.stderr).to eq($stderr)
      expect(cmd.stdin).to eq($stdin)
    end
  end

  describe "#call" do
    it "must be implemented by subclass" do
      abstract_command = described_class.new
      expect {
        abstract_command.call([])
      }.to raise_error(NotImplementedError)
    end

    it "works in concrete subclass" do
      exit_code = command.call(["--success"])
      expect(exit_code).to eq(0)
    end
  end

  describe "#success" do
    it "writes message to stdout and returns exit code 0" do
      exit_code = command.call(["--success"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Test succeeded")
      expect(stderr.string).to be_empty
    end

    it "returns exit code without message" do
      exit_code = command.call(["--no-message"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to be_empty
    end

    it "supports custom exit code" do
      # Test by checking the method directly
      exit_code = command.send(:success, "Done", exit_code: 5)
      expect(exit_code).to eq(5)
    end
  end

  describe "#failure" do
    it "writes message to stderr and returns exit code 1" do
      exit_code = command.call(["--fail"])
      expect(exit_code).to eq(2)
      expect(stderr.string).to include("Test failed")
      expect(stdout.string).to be_empty
    end

    it "supports custom exit code" do
      exit_code = command.call(["--fail"])
      expect(exit_code).to eq(2)
    end
  end

  describe "#parse_options" do
    it "parses command line options" do
      exit_code = command.call(["--name", "World"])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Hello World")
    end

    it "uses defaults for missing options" do
      exit_code = command.call([])
      expect(exit_code).to eq(0)
      expect(stdout.string).to include("Hello default")
    end

    it "returns nil and writes error for invalid options" do
      exit_code = command.call(["--invalid"])
      expect(exit_code).to eq(1)
      expect(stderr.string).to include("invalid option")
    end

    it "yields OptionParser for configuration" do
      opts = nil
      command.send(:parse_options, ["--name", "Test"], {name: "default"}) do |o|
        opts = o
        OptionParser.new do |parser|
          parser.on("--name NAME") { |v| o[:name] = v }
        end
      end
      expect(opts[:name]).to eq("Test")
    end
  end

  describe "I/O isolation" do
    it "allows testing without side effects" do
      command.call(["--success"])

      expect(stdout.string).to include("Test succeeded")
      expect(stderr.string).to be_empty

      # No output to actual stdout/stderr
      # This is testable because we're using StringIO
    end

    it "can read from custom stdin" do
      stdin.puts("test input")
      stdin.rewind

      # If command reads from stdin, it would get "test input"
      expect(command.stdin.read).to eq("test input\n")
    end
  end

  describe "exit codes" do
    it "returns 0 for success" do
      exit_code = command.call(["--success"])
      expect(exit_code).to eq(0)
    end

    it "returns non-zero for failure" do
      exit_code = command.call(["--fail"])
      expect(exit_code).to be > 0
    end

    it "returns 1 for invalid options" do
      exit_code = command.call(["--invalid"])
      expect(exit_code).to eq(1)
    end
  end
end
