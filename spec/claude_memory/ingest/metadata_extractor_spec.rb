# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Ingest::MetadataExtractor do
  subject(:extractor) { described_class.new }

  describe "#extract" do
    it "extracts git_branch from first message" do
      raw_text = '{"gitBranch": "main", "type": "system"}' + "\n"
      result = extractor.extract(raw_text)
      expect(result[:git_branch]).to eq("main")
    end

    it "extracts cwd from first message" do
      raw_text = '{"cwd": "/home/user/project"}' + "\n"
      result = extractor.extract(raw_text)
      expect(result[:cwd]).to eq("/home/user/project")
    end

    it "extracts nested metadata fields" do
      raw_text = '{"metadata": {"gitBranch": "feature", "cwd": "/tmp"}}' + "\n"
      result = extractor.extract(raw_text)
      expect(result[:git_branch]).to eq("feature")
      expect(result[:cwd]).to eq("/tmp")
    end

    it "extracts claude_version" do
      raw_text = '{"version": "4.0.1"}' + "\n"
      result = extractor.extract(raw_text)
      expect(result[:claude_version]).to eq("4.0.1")
    end

    it "extracts thinking_level" do
      raw_text = '{"thinkingMetadata": {"level": "extended"}}' + "\n"
      result = extractor.extract(raw_text)
      expect(result[:thinking_level]).to eq("extended")
    end

    it "returns empty hash for nil input" do
      expect(extractor.extract(nil)).to eq({})
    end

    it "returns empty hash for empty input" do
      expect(extractor.extract("")).to eq({})
    end

    it "returns empty hash for invalid JSON" do
      expect(extractor.extract("not json\n")).to eq({})
    end

    it "omits nil values from result" do
      raw_text = '{"gitBranch": "main"}' + "\n"
      result = extractor.extract(raw_text)
      expect(result).not_to have_key(:cwd)
      expect(result).not_to have_key(:claude_version)
    end
  end
end
