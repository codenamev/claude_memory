# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::OTel::Status do
  let(:db_path) { File.join(Dir.tmpdir, "otel_status_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:configuration) { instance_double(ClaudeMemory::Configuration, otel_traces_enabled?: false) }
  let(:settings_writer) { nil }

  subject(:status) do
    described_class.new(store, configuration: configuration, settings_writer: settings_writer)
  end

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#snapshot with no telemetry" do
    it "reports zero counts and nil timestamps" do
      snap = status.snapshot
      expect(snap[:metric_count]).to eq(0)
      expect(snap[:event_count]).to eq(0)
      expect(snap[:trace_count]).to eq(0)
      expect(snap[:last_metric_at]).to be_nil
      expect(snap[:traces_enabled]).to be(false)
      expect(snap[:configured_env]).to eq({})
      expect(snap[:endpoint]).to be_nil
    end
  end

  describe "#snapshot with rows" do
    it "counts rows and reports the latest timestamp" do
      store.insert_otel_metric(name: "claude_code.token.usage", value_type: "int",
        value_int: 100, recorded_at: "2026-07-01T00:00:00Z")
      store.insert_otel_metric(name: "claude_code.token.usage", value_type: "int",
        value_int: 200, recorded_at: "2026-07-02T00:00:00Z")
      store.insert_otel_event(event_name: "user_prompt", occurred_at: "2026-07-03T00:00:00Z")

      snap = status.snapshot
      expect(snap[:metric_count]).to eq(2)
      expect(snap[:event_count]).to eq(1)
      expect(snap[:last_metric_at]).to eq("2026-07-02T00:00:00Z")
      expect(snap[:last_event_at]).to eq("2026-07-03T00:00:00Z")
    end
  end

  describe "missing-table guards" do
    it "returns 0 / nil when a table is absent" do
      allow(store.db).to receive(:table_exists?).and_return(false)
      snap = status.snapshot
      expect(snap[:metric_count]).to eq(0)
      expect(snap[:last_metric_at]).to be_nil
    end
  end

  describe "configured_env" do
    context "with an injected settings_writer" do
      let(:settings_writer) do
        instance_double(ClaudeMemory::OTel::SettingsWriter,
          current_env: {"OTEL_EXPORTER_OTLP_ENDPOINT" => "http://localhost:4318"})
      end

      it "surfaces the env and endpoint" do
        snap = status.snapshot
        expect(snap[:configured_env]).to eq("OTEL_EXPORTER_OTLP_ENDPOINT" => "http://localhost:4318")
        expect(snap[:endpoint]).to eq("http://localhost:4318")
      end
    end

    context "when the settings file is missing or malformed" do
      let(:settings_writer) { instance_double(ClaudeMemory::OTel::SettingsWriter) }

      it "falls back to an empty env" do
        allow(settings_writer).to receive(:current_env).and_raise(Errno::ENOENT)
        expect(status.snapshot[:configured_env]).to eq({})
      end
    end
  end
end
