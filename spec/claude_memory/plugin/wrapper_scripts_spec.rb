# frozen_string_literal: true

require "open3"

RSpec.describe "Plugin wrapper scripts" do
  let(:project_root) { File.expand_path("../../..", __dir__) }
  let(:bash) { "/bin/bash" }

  describe "scripts/serve-mcp.sh" do
    let(:script) { File.join(project_root, "scripts", "serve-mcp.sh") }

    context "when claude-memory is not in PATH" do
      it "outputs JSON-RPC error and exits 1" do
        stdout, _stderr, status = Open3.capture3(
          {"PATH" => "/nonexistent"},
          bash, script
        )
        expect(status.exitstatus).to eq(1)
        expect(stdout).to include("jsonrpc")
        expect(stdout).to include("claude-memory gem not found")
      end
    end
  end

  describe "scripts/hook-runner.sh" do
    let(:script) { File.join(project_root, "scripts", "hook-runner.sh") }

    context "when claude-memory is not in PATH" do
      it "outputs install message to stderr and exits 0" do
        _stdout, stderr, status = Open3.capture3(
          {"PATH" => "/nonexistent"},
          bash, script, "ingest",
          stdin_data: "{}"
        )
        expect(status.exitstatus).to eq(0)
        expect(stderr).to include("gem install claude_memory")
      end
    end
  end
end
