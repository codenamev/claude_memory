# frozen_string_literal: true

require "json"

RSpec.describe ClaudeMemory::OTel::OtlpJsonEnvelope do
  fixture_dir = File.expand_path("../../fixtures/otel", __dir__)

  describe ".parse_metrics" do
    let(:payload) { JSON.parse(File.read(File.join(fixture_dir, "metrics_envelope.json"))) }

    it "flattens KeyValue attribute arrays into plain hashes" do
      rows = described_class.parse_metrics(payload)
      first = rows.first
      expect(first[:attributes]).to include("type" => "input", "model" => "claude-sonnet-4-6")
      expect(first[:resource]).to include("service.name" => "claude-code", "os.type" => "darwin")
    end

    it "routes int dataPoints to value_int and double dataPoints to value_float" do
      rows = described_class.parse_metrics(payload)
      tokens = rows.find { |r| r[:name] == "claude_code.token.usage" && r[:attributes]["type"] == "input" }
      expect(tokens[:value_type]).to eq("int")
      expect(tokens[:value_int]).to eq(1234)
      expect(tokens[:value_float]).to be_nil

      cost = rows.find { |r| r[:name] == "claude_code.cost.usage" }
      expect(cost[:value_type]).to eq("double")
      expect(cost[:value_int]).to be_nil
      expect(cost[:value_float]).to be_within(1e-9).of(0.0042)
    end

    it "converts timeUnixNano to ISO 8601 deterministically" do
      rows = described_class.parse_metrics(payload)
      expect(rows.first[:recorded_at]).to eq("2023-11-14T22:13:20Z")
    end

    it "emits one row per data point" do
      rows = described_class.parse_metrics(payload)
      expect(rows.size).to eq(3) # 2 token rows + 1 cost row
    end

    it "is pure: no Time.now is called when timestamps are present" do
      injected_clock = double("clock")
      expect(injected_clock).not_to receive(:now)
      described_class.parse_metrics(payload, clock: injected_clock)
    end

    it "falls back to the injected clock only when timeUnixNano is missing" do
      payload_no_time = JSON.parse(payload.to_json)
      payload_no_time["resourceMetrics"][0]["scopeMetrics"][0]["metrics"][0]["sum"]["dataPoints"][0].delete("timeUnixNano")
      fake_now = Time.utc(2030, 1, 1, 12, 0, 0)
      injected_clock = double("clock", now: fake_now)
      rows = described_class.parse_metrics(payload_no_time, clock: injected_clock)
      expect(rows.first[:recorded_at]).to eq(fake_now.iso8601)
    end

    it "tolerates an empty payload" do
      expect(described_class.parse_metrics({})).to eq([])
    end

    it "raises when required `name` field is missing" do
      bad = {
        "resourceMetrics" => [{
          "scopeMetrics" => [{"metrics" => [{"unit" => "tokens", "sum" => {"dataPoints" => [{"asInt" => "1"}]}}]}]
        }]
      }
      expect { described_class.parse_metrics(bad) }.to raise_error(KeyError)
    end
  end

  describe ".parse_logs" do
    let(:payload) { JSON.parse(File.read(File.join(fixture_dir, "logs_envelope.json"))) }

    it "extracts event name from event.name attribute, stripping claude_code. prefix" do
      rows = described_class.parse_logs(payload)
      expect(rows.map { |r| r[:event_name] }).to contain_exactly("user_prompt", "tool_result")
    end

    it "extracts session_id and prompt_id" do
      rows = described_class.parse_logs(payload)
      expect(rows.first[:session_id]).to eq("abc-123")
      expect(rows.first[:prompt_id]).to eq("p-1")
    end

    it "preserves int64-encoded attribute values as integers" do
      rows = described_class.parse_logs(payload)
      first = rows.find { |r| r[:event_name] == "user_prompt" }
      expect(first[:attributes]["prompt_length"]).to eq(42)
    end
  end

  describe ".flatten_attributes" do
    it "decodes each OTel value variant" do
      kvs = [
        {"key" => "s", "value" => {"stringValue" => "hi"}},
        {"key" => "i", "value" => {"intValue" => "9223372036854775807"}},
        {"key" => "d", "value" => {"doubleValue" => 1.5}},
        {"key" => "b", "value" => {"boolValue" => true}}
      ]
      expect(described_class.flatten_attributes(kvs)).to eq(
        "s" => "hi",
        "i" => 9_223_372_036_854_775_807,
        "d" => 1.5,
        "b" => true
      )
    end
  end
end
