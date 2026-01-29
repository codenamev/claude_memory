# frozen_string_literal: true

require "spec_helper"
require "claude_memory/mcp/setup_status_analyzer"

RSpec.describe ClaudeMemory::MCP::SetupStatusAnalyzer do
  describe ".determine_status" do
    it "returns healthy when initialized and version is up to date" do
      status = described_class.determine_status(true, true, "up_to_date")

      expect(status).to eq("healthy")
    end

    it "returns needs_upgrade when initialized but version is outdated" do
      status = described_class.determine_status(true, true, "outdated")

      expect(status).to eq("needs_upgrade")
    end

    it "returns partially_initialized when global DB exists but no CLAUDE.md" do
      status = described_class.determine_status(true, false, nil)

      expect(status).to eq("partially_initialized")
    end

    it "returns not_initialized when global DB doesn't exist" do
      status = described_class.determine_status(false, true, nil)

      expect(status).to eq("not_initialized")
    end

    it "returns not_initialized when neither component exists" do
      status = described_class.determine_status(false, false, nil)

      expect(status).to eq("not_initialized")
    end

    it "returns partially_initialized even with up_to_date version if CLAUDE.md missing" do
      status = described_class.determine_status(true, false, "up_to_date")

      expect(status).to eq("partially_initialized")
    end
  end

  describe ".generate_recommendations" do
    it "recommends init when not initialized" do
      recommendations = described_class.generate_recommendations(false, nil, false)

      expect(recommendations).to include("Run: claude-memory init")
      expect(recommendations).to include("This will create databases, configure hooks, and set up CLAUDE.md")
      expect(recommendations.length).to eq(2)
    end

    it "recommends upgrade when version is outdated" do
      recommendations = described_class.generate_recommendations(true, "outdated", false)

      expect(recommendations).to include("Run: claude-memory upgrade (when available)")
      expect(recommendations).to include("Or manually run: claude-memory init to update CLAUDE.md")
      expect(recommendations.length).to eq(2)
    end

    it "recommends doctor when there are warnings" do
      recommendations = described_class.generate_recommendations(true, "up_to_date", true)

      expect(recommendations).to include("Run: claude-memory doctor --fix (when available)")
      expect(recommendations).to include("Or check individual issues and fix manually")
      expect(recommendations.length).to eq(2)
    end

    it "returns empty when initialized, up to date, and no warnings" do
      recommendations = described_class.generate_recommendations(true, "up_to_date", false)

      expect(recommendations).to eq([])
    end

    it "prioritizes init over other recommendations when not initialized" do
      recommendations = described_class.generate_recommendations(false, "outdated", true)

      expect(recommendations.first).to include("claude-memory init")
    end

    it "prioritizes upgrade over warnings" do
      recommendations = described_class.generate_recommendations(true, "outdated", true)

      expect(recommendations.first).to include("upgrade")
      expect(recommendations).not_to include(match(/doctor/))
    end
  end

  describe ".extract_version" do
    it "extracts version from valid HTML comment" do
      content = "Some text\n<!-- ClaudeMemory v1.2.3 -->\nMore text"

      version = described_class.extract_version(content)

      expect(version).to eq("1.2.3")
    end

    it "returns nil when no version marker found" do
      content = "Some text without version marker"

      version = described_class.extract_version(content)

      expect(version).to be_nil
    end

    it "extracts version with multiple digits" do
      content = "<!-- ClaudeMemory v10.20.30 -->"

      version = described_class.extract_version(content)

      expect(version).to eq("10.20.30")
    end

    it "returns nil for invalid version format" do
      content = "<!-- ClaudeMemory vX.Y.Z -->"

      version = described_class.extract_version(content)

      expect(version).to be_nil
    end

    it "extracts first match if multiple markers" do
      content = "<!-- ClaudeMemory v1.0.0 -->\n<!-- ClaudeMemory v2.0.0 -->"

      version = described_class.extract_version(content)

      expect(version).to eq("1.0.0")
    end
  end

  describe ".determine_version_status" do
    it "returns up_to_date when versions match" do
      status = described_class.determine_version_status("1.5.0", "1.5.0")

      expect(status).to eq("up_to_date")
    end

    it "returns outdated when current version is older" do
      status = described_class.determine_version_status("1.4.0", "1.5.0")

      expect(status).to eq("outdated")
    end

    it "returns outdated when current version format differs but not equal" do
      status = described_class.determine_version_status("1.0", "1.0.0")

      expect(status).to eq("outdated")
    end

    it "returns unknown when current version is nil" do
      status = described_class.determine_version_status(nil, "1.5.0")

      expect(status).to eq("unknown")
    end

    it "handles version string comparison (not semantic)" do
      status = described_class.determine_version_status("2.0.0", "1.9.9")

      expect(status).to eq("outdated")
    end
  end
end
