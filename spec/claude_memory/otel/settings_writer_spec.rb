# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::OTel::SettingsWriter do
  let(:tmpdir) { Dir.mktmpdir("settings_writer_#{Process.pid}") }
  let(:claude_dir) { File.join(tmpdir, ".claude") }
  let(:settings_path) { File.join(claude_dir, "settings.json") }
  let(:writer) { described_class.new(claude_dir, port: 3399) }

  after { FileUtils.rm_rf(tmpdir) }

  it "writes the OTel env block when enabling for the first time" do
    expect(writer.enable!).to be_success
    parsed = JSON.parse(File.read(settings_path))
    expect(parsed["env"]).to include(
      "CLAUDE_CODE_ENABLE_TELEMETRY" => "1",
      "OTEL_EXPORTER_OTLP_PROTOCOL" => "http/json",
      "OTEL_EXPORTER_OTLP_ENDPOINT" => "http://127.0.0.1:3399",
      "OTEL_METRICS_EXPORTER" => "otlp",
      "OTEL_LOGS_EXPORTER" => "otlp"
    )
  end

  it "preserves unrelated keys in settings.json" do
    FileUtils.mkdir_p(claude_dir)
    File.write(settings_path, JSON.generate(env: {"FOO" => "bar"}, hooks: {"x" => "y"}))
    writer.enable!
    parsed = JSON.parse(File.read(settings_path))
    expect(parsed["env"]["FOO"]).to eq("bar")
    expect(parsed["hooks"]).to eq("x" => "y")
  end

  it "is idempotent" do
    writer.enable!
    expect(writer.enable!).to be_success
    parsed = JSON.parse(File.read(settings_path))
    expect(parsed["env"]).to include("CLAUDE_CODE_ENABLE_TELEMETRY" => "1")
  end

  it "removes only owned keys on disable" do
    FileUtils.mkdir_p(claude_dir)
    File.write(settings_path, JSON.generate(env: {"FOO" => "bar"}))
    writer.enable!
    writer.disable!
    parsed = JSON.parse(File.read(settings_path))
    expect(parsed["env"]).to eq("FOO" => "bar")
  end

  describe "privacy contract" do
    it "does NOT set OTEL_LOG_USER_PROMPTS by default" do
      writer.enable!
      parsed = JSON.parse(File.read(settings_path))
      expect(parsed["env"]).not_to have_key("OTEL_LOG_USER_PROMPTS")
    end

    it "only sets OTEL_LOG_USER_PROMPTS when capture_prompts! is called" do
      writer.capture_prompts!
      parsed = JSON.parse(File.read(settings_path))
      expect(parsed["env"]["OTEL_LOG_USER_PROMPTS"]).to eq("1")
    end
  end

  describe "traces" do
    it "does NOT set OTEL_TRACES_EXPORTER on enable!" do
      writer.enable!
      parsed = JSON.parse(File.read(settings_path))
      expect(parsed["env"]).not_to have_key("OTEL_TRACES_EXPORTER")
    end

    it "sets OTEL_TRACES_EXPORTER=otlp on enable_traces!" do
      writer.enable_traces!
      parsed = JSON.parse(File.read(settings_path))
      expect(parsed["env"]["OTEL_TRACES_EXPORTER"]).to eq("otlp")
    end

    it "sets OTEL_TRACES_EXPORTER=none on disable_traces! to silence Claude Code" do
      writer.disable_traces!
      parsed = JSON.parse(File.read(settings_path))
      expect(parsed["env"]["OTEL_TRACES_EXPORTER"]).to eq("none")
    end
  end
end
