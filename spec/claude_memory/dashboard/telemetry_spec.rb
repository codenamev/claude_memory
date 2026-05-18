# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Telemetry do
  let(:tmpdir) { Dir.mktmpdir("telemetry_panel_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", "memory.sqlite3") }
  let(:manager) do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end
  let(:panel) { described_class.new(manager) }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  describe "#snapshot" do
    it "returns the empty shape when no metrics rows exist" do
      result = panel.snapshot
      expect(result[:cost_over_time]).to eq([])
      expect(result[:tokens_by_model]).to eq([])
      expect(result[:top_tools_by_latency]).to eq([])
      expect(result[:error_rate]).to eq(total: 0, errors: 0, ratio: 0.0)
      expect(result[:contains_prompt_content]).to be false
    end

    it "returns a status payload regardless of row presence" do
      result = panel.snapshot
      expect(result[:status]).to include(:metric_count, :traces_enabled)
    end
  end

  context "with seeded rows" do
    let(:store) { manager.global_store }

    before do
      ts = Time.now.utc.iso8601
      store.insert_otel_metric(
        name: "claude_code.cost.usage", value_type: "double", value_float: 0.0042,
        unit: "USD", attributes: {"model" => "claude-sonnet-4-6"}, recorded_at: ts
      )
      store.insert_otel_metric(
        name: "claude_code.token.usage", value_type: "int", value_int: 1234,
        unit: "tokens", attributes: {"type" => "input", "model" => "claude-sonnet-4-6"}, recorded_at: ts
      )
      store.insert_otel_metric(
        name: "claude_code.token.usage", value_type: "int", value_int: 456,
        unit: "tokens", attributes: {"type" => "output", "model" => "claude-sonnet-4-6"}, recorded_at: ts
      )
    end

    it "aggregates cost-over-time by hour bucket" do
      bins = panel.snapshot[:cost_over_time]
      expect(bins.size).to eq(1)
      expect(bins.first[:requests]).to eq(1)
      expect(bins.first[:cost_usd]).to be_within(1e-6).of(0.0042)
    end

    it "aggregates tokens grouped by (model, type)" do
      tokens = panel.snapshot[:tokens_by_model]
      input = tokens.find { |t| t[:type] == "input" }
      output = tokens.find { |t| t[:type] == "output" }
      expect(input[:tokens]).to eq(1234)
      expect(output[:tokens]).to eq(456)
    end
  end
end
