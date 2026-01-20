# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"
require "json"

RSpec.describe ClaudeMemory::MCP::Server do
  let(:db_path) { File.join(Dir.tmpdir, "mcp_server_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  let(:server) { described_class.new(store, input: input, output: output) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def send_request(request)
    input.puts(JSON.generate(request))
    input.rewind
    server.run
    output.rewind
    JSON.parse(output.read.strip)
  end

  describe "initialize" do
    it "responds with capabilities" do
      response = send_request({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {}
      })

      expect(response["result"]["protocolVersion"]).to eq(described_class::PROTOCOL_VERSION)
      expect(response["result"]["serverInfo"]["name"]).to eq("claude-memory")
    end
  end

  describe "tools/list" do
    it "returns available tools" do
      response = send_request({
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list"
      })

      tools = response["result"]["tools"]
      expect(tools.map { |t| t["name"] }).to include("memory.recall", "memory.status")
    end
  end

  describe "tools/call" do
    it "calls a tool and returns result" do
      response = send_request({
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "memory.status",
          arguments: {}
        }
      })

      content = response["result"]["content"]
      expect(content.first["type"]).to eq("text")
      result = JSON.parse(content.first["text"])
      expect(result["schema_version"]).to eq(1)
    end
  end

  describe "unknown method" do
    it "returns method not found error" do
      response = send_request({
        jsonrpc: "2.0",
        id: 4,
        method: "unknown/method"
      })

      expect(response["error"]["code"]).to eq(-32601)
      expect(response["error"]["message"]).to include("Method not found")
    end
  end

  describe "invalid JSON" do
    it "returns parse error" do
      input.puts("not valid json")
      input.rewind
      server.run
      output.rewind
      response = JSON.parse(output.read.strip)

      expect(response["error"]["code"]).to eq(-32700)
    end
  end
end
