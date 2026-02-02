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
    it "returns text summary in content" do
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
      expect(content.first["text"]).to include("Memory status:")
    end

    it "returns structured data in structuredContent" do
      response = send_request({
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "memory.status",
          arguments: {}
        }
      })

      structured = response["result"]["structuredContent"]
      expect(structured).to be_a(Hash)
      expect(structured["databases"]["legacy"]["schema_version"]).to eq(7)
    end
  end

  describe "prompts/list" do
    it "returns available prompts" do
      response = send_request({
        jsonrpc: "2.0",
        id: 5,
        method: "prompts/list"
      })

      prompts = response["result"]["prompts"]
      expect(prompts.map { |p| p["name"] }).to include("memory_guide")
    end
  end

  describe "prompts/get" do
    it "returns memory_guide prompt content" do
      response = send_request({
        jsonrpc: "2.0",
        id: 6,
        method: "prompts/get",
        params: {name: "memory_guide"}
      })

      messages = response["result"]["messages"]
      expect(messages).to be_an(Array)
      expect(messages.first["role"]).to eq("user")
      expect(messages.first["content"]["text"]).to include("memory.recall")
    end

    it "returns error for unknown prompt" do
      response = send_request({
        jsonrpc: "2.0",
        id: 7,
        method: "prompts/get",
        params: {name: "nonexistent"}
      })

      expect(response["error"]["code"]).to eq(-32602)
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
