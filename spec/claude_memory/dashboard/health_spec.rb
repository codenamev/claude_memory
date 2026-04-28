# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Dashboard::Health do
  let(:tmpdir) { Dir.mktmpdir("dashboard_health_#{Process.pid}") }
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
  let(:health) { described_class.new(manager) }

  after do
    manager&.close
    FileUtils.rm_rf(tmpdir)
  end

  describe "#report" do
    it "warns on uninitialized databases and missing hooks" do
      Dir.chdir(tmpdir) do
        result = health.report
        expect(result[:status]).to eq("error") # missing hooks is an error
        expect(result[:version]).to eq(ClaudeMemory::VERSION)

        names = result[:checks].map { |c| c[:name] }
        expect(names).to contain_exactly("global_database", "project_database", "hooks", "vectors")

        global = result[:checks].find { |c| c[:name] == "global_database" }
        expect(global[:status]).to eq("warning")
        expect(global[:fix]).to include("claude-memory init")
      end
    end

    it "reports healthy databases once initialized" do
      manager.ensure_both!
      Dir.chdir(tmpdir) do
        # Stub hooks settings as healthy so the only signal is the DB checks
        FileUtils.mkdir_p(".claude")
        File.write(".claude/settings.json", {hooks: stub_hooks_settings}.to_json)

        result = health.report
        global = result[:checks].find { |c| c[:name] == "global_database" }
        project = result[:checks].find { |c| c[:name] == "project_database" }
        expect(global[:status]).to eq("healthy")
        expect(project[:status]).to eq("healthy")
        expect(global[:message]).to match(/Schema v\d+/)
      end
    end

    it "warns on partial hook configuration" do
      manager.ensure_both!
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p(".claude")
        File.write(".claude/settings.json", {hooks: {
          "Stop" => [{"hooks" => [{"type" => "command", "command" => "claude-memory hook ingest"}]}]
        }}.to_json)

        result = health.report
        hooks = result[:checks].find { |c| c[:name] == "hooks" }
        expect(hooks[:status]).to eq("warning")
        expect(hooks[:fix]).to include("Missing hook")
      end
    end

    it "treats settings without claude-memory as no-hooks-installed" do
      manager.ensure_both!
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p(".claude")
        File.write(".claude/settings.json", {hooks: {
          "Stop" => [{"hooks" => [{"type" => "command", "command" => "echo hi"}]}]
        }}.to_json)

        result = health.report
        hooks = result[:checks].find { |c| c[:name] == "hooks" }
        expect(hooks[:status]).to eq("error")
        expect(hooks[:message]).to include("No claude-memory hooks found")
      end
    end

    it "handles unreadable hook settings via the rescue path" do
      manager.ensure_both!
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p(".claude")
        File.write(".claude/settings.json", "{not json")

        result = health.report
        hooks = result[:checks].find { |c| c[:name] == "hooks" }
        expect(hooks[:status]).to eq("error")
        expect(hooks[:fix]).to include("valid JSON")
      end
    end

    it "elevates overall status to error when any check is error" do
      Dir.chdir(tmpdir) do
        result = health.report
        # No hooks installed → hooks check is error → overall is error
        expect(result[:status]).to eq("error")
      end
    end

    it "aggregates per-check status into the report-level status" do
      manager.ensure_both!
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p(".claude")
        File.write(".claude/settings.json", {hooks: stub_hooks_settings}.to_json)

        result = health.report
        statuses = result[:checks].map { |c| c[:status] }
        expected = expected_aggregate(statuses)
        expect(result[:status]).to eq(expected)
      end
    end
  end

  def expected_aggregate(statuses)
    return "error" if statuses.include?("error")
    return "warning" if statuses.include?("warning")
    "healthy"
  end

  def stub_hooks_settings
    expected = ClaudeMemory::Commands::Checks::HooksCheck::EXPECTED_HOOKS
    expected.each_with_object({}) do |event, acc|
      acc[event] = [{"hooks" => [{"type" => "command", "command" => "claude-memory hook ingest"}]}]
    end
  end
end
