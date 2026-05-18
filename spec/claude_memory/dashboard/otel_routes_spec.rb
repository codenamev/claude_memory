# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "net/http"
require "uri"

# Negative-contract tests for the OTel routes on Dashboard::Server. Each
# example locks one promise we don't want silently regressing.
RSpec.describe "Dashboard OTel routes" do
  let(:tmpdir) { Dir.mktmpdir("otel_routes_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", "memory.sqlite3") }
  let(:port) { random_port }
  let(:manager) do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end
  let(:server) { ClaudeMemory::Dashboard::Server.new(manager: manager, port: port, open_browser: false) }
  let(:server_thread) { Thread.new { server.start } }

  before do
    manager.ensure_both!
    server_thread
    wait_for_port(port)
  end

  after do
    server.stop
    server_thread.join(2)
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  it "binds only to 127.0.0.1 (binding contract)" do
    skip "platform exposes other interfaces" unless system("ifconfig", "lo0", out: File::NULL, err: File::NULL)
    # If the server were listening on 0.0.0.0 we'd be able to reach it via
    # any other local IP. The simplest binding-contract check is that the
    # WEBrick server's bind address is exactly "127.0.0.1".
    inner_server = server.instance_variable_get(:@server)
    expect(inner_server.config[:BindAddress]).to eq("127.0.0.1")
  end

  it "rejects /v1/metrics with 415 when Content-Type is application/x-protobuf (protocol contract)" do
    res = post("/v1/metrics", "{}", "application/x-protobuf")
    expect(res.code).to eq("415")
  end

  it "accepts /v1/metrics with application/json and writes rows" do
    payload = {
      "resourceMetrics" => [{
        "scopeMetrics" => [{"metrics" => [{
          "name" => "claude_code.token.usage", "unit" => "tokens",
          "sum" => {"dataPoints" => [{"asInt" => "1", "timeUnixNano" => "1700000000000000000",
                                      "attributes" => []}]}
        }]}]
      }]
    }
    res = post("/v1/metrics", JSON.generate(payload))
    expect(res.code).to eq("200")
    expect(manager.global_store.otel_metrics.count).to eq(1)
  end

  it "returns 501 on /v1/traces when traces are not enabled (gate contract)" do
    res = post("/v1/traces", "{}")
    expect(res.code).to eq("501")
    expect(manager.global_store.otel_traces.count).to eq(0)
  end

  it "writes 0 rows when /v1/traces is hit while gated (gate contract)" do
    expect {
      3.times { post("/v1/traces", "{}") }
    }.not_to(change { manager.global_store.otel_traces.count })
  end

  private

  def post(path, body, content_type = "application/json")
    uri = URI.parse("http://127.0.0.1:#{port}#{path}")
    req = Net::HTTP::Post.new(uri.path, "Content-Type" => content_type)
    req.body = body
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 2) { |http| http.request(req) }
  end

  def random_port
    socket = TCPServer.new("127.0.0.1", 0)
    port = socket.addr[1]
    socket.close
    port
  end

  def wait_for_port(port, attempts: 50)
    attempts.times do
      socket = TCPSocket.new("127.0.0.1", port)
      socket.close
      return
    rescue Errno::ECONNREFUSED
      sleep 0.05
    end
    raise "server did not come up on port #{port}"
  end
end
