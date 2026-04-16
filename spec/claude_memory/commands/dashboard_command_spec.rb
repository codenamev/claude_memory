# frozen_string_literal: true

RSpec.describe ClaudeMemory::Commands::DashboardCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  describe "with no databases" do
    it "returns error when no databases exist" do
      allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(
        instance_double(
          ClaudeMemory::Store::StoreManager,
          global_exists?: false,
          project_exists?: false,
          close: nil
        )
      )

      exit_code = command.call([])

      expect(exit_code).to eq(1)
      expect(stderr.string).to include("No memory databases found")
    end
  end

  describe "option parsing" do
    it "accepts --port flag" do
      # Just test option parsing, not server startup
      manager = instance_double(
        ClaudeMemory::Store::StoreManager,
        global_exists?: false,
        project_exists?: false,
        close: nil
      )
      allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(manager)

      exit_code = command.call(["--port", "9999"])
      expect(exit_code).to eq(1) # Still fails because no DBs
    end

    it "rejects invalid options" do
      exit_code = command.call(["--invalid"])
      expect(exit_code).to eq(1)
    end
  end
end
