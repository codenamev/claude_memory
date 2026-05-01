# frozen_string_literal: true

require "yaml"
require "json"
require "tmpdir"
require "fileutils"

# Loads the script directly so we can drive `PreReleaseSmoke#run` with
# stubs instead of actually invoking `rake install` + the gem binary.
# Spec covers the manifest schema and the exit-code branches; the real
# `bin/pre-release-smoke` invocation is what the /release skill runs.
load File.expand_path("../../bin/pre-release-smoke", __dir__)

RSpec.describe PreReleaseSmoke do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:tmpdir) { Dir.mktmpdir("pre_release_smoke_spec_") }
  let(:manifest_path) { File.join(tmpdir, "manifest.yml") }
  let(:smoke) { described_class.new(manifest_path: manifest_path, stdout: stdout, stderr: stderr) }

  after { FileUtils.rm_rf(tmpdir) }

  def write_manifest(data)
    File.write(manifest_path, data.to_yaml)
  end

  describe "manifest validation" do
    it "fails fast when the manifest file doesn't exist" do
      missing = File.join(tmpdir, "absent.yml")
      smoke = described_class.new(manifest_path: missing, stdout: stdout, stderr: stderr)

      expect(smoke.run).to eq(1)
      expect(stderr.string).to include("Manifest missing")
    end

    it "fails when the manifest doesn't have an events array" do
      File.write(manifest_path, {"foo" => "bar"}.to_yaml)
      expect(smoke.run).to eq(1)
      expect(stderr.string).to include("'events:' array")
    end
  end

  describe "exit-code logic on simulated detail_json" do
    before do
      write_manifest({
        "events" => [
          {
            "event_type" => "hook_context",
            "description" => "test",
            "status" => "success",
            "fields" => [
              {"name" => "context_length", "since_version" => "0.10.0"},
              {"name" => "context_tokens", "since_version" => "0.11.0"}
            ]
          }
        ]
      })

      # Stub the slow / external steps so we only exercise the
      # manifest + verification logic.
      allow(smoke).to receive(:install_gem)
      allow(smoke).to receive(:verify_binary_on_path)
      allow(smoke).to receive(:seed_database)
      allow(smoke).to receive(:trigger_hooks)
    end

    it "returns 0 when every expected field is present in the latest event row" do
      allow(smoke).to receive(:fetch_latest_detail_json)
        .and_return({"context_length" => 8826, "context_tokens" => 2206}.to_json)

      expect(smoke.run).to eq(0)
      expect(stdout.string).to include("PASSED")
    end

    it "returns 1 and names the missing field when one expected key is null" do
      allow(smoke).to receive(:fetch_latest_detail_json)
        .and_return({"context_length" => 8826, "context_tokens" => nil}.to_json)

      expect(smoke.run).to eq(1)
      expect(stderr.string).to include("hook_context")
      expect(stderr.string).to include("context_tokens")
      expect(stderr.string).to include("0.11.0")
    end

    it "returns 1 when an expected key is entirely absent from detail_json" do
      allow(smoke).to receive(:fetch_latest_detail_json)
        .and_return({"context_length" => 8826}.to_json)

      expect(smoke.run).to eq(1)
      expect(stderr.string).to include("context_tokens")
    end

    it "returns 1 when no matching activity_events row exists at all" do
      allow(smoke).to receive(:fetch_latest_detail_json).and_return(nil)

      expect(smoke.run).to eq(1)
      expect(stderr.string).to include("hook didn't fire")
    end

    it "treats empty arrays and zeros as present (only nil counts as missing)" do
      # Some fields are legitimately empty in the silent-success case
      # (e.g. top_fact_ids: [] when no facts were emitted). The gate
      # checks for the *presence* of the field, not its non-emptiness.
      allow(smoke).to receive(:fetch_latest_detail_json)
        .and_return({"context_length" => 0, "context_tokens" => 0}.to_json)

      expect(smoke.run).to eq(0)
    end
  end

  describe "shipped manifest" do
    let(:shipped_manifest) { YAML.load_file(File.expand_path("expected_fields.yml", __dir__)) }

    it "loads as a hash with an events array" do
      expect(shipped_manifest).to be_a(Hash)
      expect(shipped_manifest["events"]).to be_an(Array)
      expect(shipped_manifest["events"]).not_to be_empty
    end

    it "has every entry shaped {event_type, description, status, fields[{name, since_version}]}" do
      shipped_manifest["events"].each do |entry|
        expect(entry).to include("event_type", "description", "status", "fields")
        expect(entry["fields"]).to be_an(Array)
        entry["fields"].each do |field|
          expect(field).to include("name", "since_version")
        end
      end
    end

    it "covers the hook_context event with both context_length and context_tokens" do
      ctx = shipped_manifest["events"].find { |e| e["event_type"] == "hook_context" }
      expect(ctx).not_to be_nil

      field_names = ctx["fields"].map { |f| f["name"] }
      expect(field_names).to include("context_length", "context_tokens")
    end

    it "covers the roi_nudge event with all 0.11 fields" do
      nudge = shipped_manifest["events"].find { |e| e["event_type"] == "roi_nudge" }
      expect(nudge).not_to be_nil

      field_names = nudge["fields"].map { |f| f["name"] }
      expect(field_names).to include("n", "used", "pct", "prior_count")
    end
  end
end
