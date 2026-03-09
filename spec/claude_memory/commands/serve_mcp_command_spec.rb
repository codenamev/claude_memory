# frozen_string_literal: true

require "stringio"

RSpec.describe ClaudeMemory::Commands::ServeMcpCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  describe "#call" do
    it "redirects $stdout to $stderr during MCP serve to protect protocol" do
      original_stdout = $stdout
      captured_stdout_during_run = nil

      allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(double("manager", close: nil))

      allow(ClaudeMemory::MCP::Server).to receive(:new) { |_manager, output:|
        # During server creation, $stdout should be redirected away from original
        captured_stdout_during_run = $stdout
        server = double("server")
        allow(server).to receive(:run)
        server
      }

      command.call([])

      # $stdout was redirected to $stderr during server operation
      expect(captured_stdout_during_run).to equal($stderr)

      # $stdout is restored after call completes
      expect($stdout).to equal(original_stdout)
    end

    it "passes dedicated output IO to MCP server" do
      captured_output = nil

      allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(double("manager", close: nil))

      allow(ClaudeMemory::MCP::Server).to receive(:new) { |_manager, output:|
        captured_output = output
        server = double("server")
        allow(server).to receive(:run)
        server
      }

      command.call([])

      # Server receives a dedicated IO for protocol output (not $stderr)
      expect(captured_output).to be_an(IO)
      expect(captured_output).not_to equal($stderr)
    end

    it "restores $stdout even if server raises an error" do
      original_stdout = $stdout

      allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(double("manager", close: nil))
      allow(ClaudeMemory::MCP::Server).to receive(:new).and_raise(RuntimeError, "test error")

      expect { command.call([]) }.to raise_error(RuntimeError, "test error")

      # $stdout must be restored despite the error
      expect($stdout).to equal(original_stdout)
    end
  end
end
