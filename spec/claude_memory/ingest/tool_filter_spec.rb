# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Ingest::ToolFilter do
  describe "#capture?" do
    context "with default skip list" do
      let(:filter) { described_class.new }

      it "skips Read tool" do
        expect(filter.capture?("Read")).to be false
      end

      it "skips Glob tool" do
        expect(filter.capture?("Glob")).to be false
      end

      it "skips Grep tool" do
        expect(filter.capture?("Grep")).to be false
      end

      it "captures Edit tool" do
        expect(filter.capture?("Edit")).to be true
      end

      it "captures Write tool" do
        expect(filter.capture?("Write")).to be true
      end

      it "captures Bash tool" do
        expect(filter.capture?("Bash")).to be true
      end

      it "returns false for nil tool name" do
        expect(filter.capture?(nil)).to be false
      end
    end

    context "with custom skip list" do
      let(:filter) { described_class.new(skip_tools: %w[Bash Edit]) }

      it "skips listed tools" do
        expect(filter.capture?("Bash")).to be false
        expect(filter.capture?("Edit")).to be false
      end

      it "captures non-listed tools" do
        expect(filter.capture?("Read")).to be true
        expect(filter.capture?("Write")).to be true
      end
    end

    context "with capture list (whitelist mode)" do
      let(:filter) { described_class.new(capture_tools: %w[Edit Write Bash]) }

      it "captures listed tools" do
        expect(filter.capture?("Edit")).to be true
        expect(filter.capture?("Write")).to be true
        expect(filter.capture?("Bash")).to be true
      end

      it "skips non-listed tools" do
        expect(filter.capture?("Read")).to be false
        expect(filter.capture?("Glob")).to be false
      end
    end

    context "whitelist takes precedence over blacklist" do
      let(:filter) { described_class.new(skip_tools: %w[Read], capture_tools: %w[Read Write]) }

      it "uses whitelist when both are provided" do
        # Read is in both skip and capture - capture_tools takes precedence
        expect(filter.capture?("Read")).to be true
        expect(filter.capture?("Write")).to be true
        expect(filter.capture?("Bash")).to be false
      end
    end
  end

  describe "#filter" do
    let(:filter) { described_class.new }

    it "removes skipped tool calls" do
      tool_calls = [
        {tool_name: "Read", tool_input: '{"file": "test.rb"}'},
        {tool_name: "Edit", tool_input: '{"file": "test.rb"}'},
        {tool_name: "Glob", tool_input: '{"pattern": "*.rb"}'}
      ]

      filtered = filter.filter(tool_calls)

      expect(filtered.length).to eq(1)
      expect(filtered.first[:tool_name]).to eq("Edit")
    end

    it "returns empty array when all tools skipped" do
      tool_calls = [
        {tool_name: "Read", tool_input: "{}"},
        {tool_name: "Grep", tool_input: "{}"}
      ]

      expect(filter.filter(tool_calls)).to eq([])
    end

    it "returns all tools when none are skipped" do
      tool_calls = [
        {tool_name: "Edit", tool_input: "{}"},
        {tool_name: "Write", tool_input: "{}"}
      ]

      expect(filter.filter(tool_calls).length).to eq(2)
    end

    it "handles empty input" do
      expect(filter.filter([])).to eq([])
    end
  end

  describe ".allow_all" do
    it "creates a filter that captures all tools" do
      filter = described_class.allow_all

      expect(filter.capture?("Read")).to be true
      expect(filter.capture?("Glob")).to be true
      expect(filter.capture?("Grep")).to be true
      expect(filter.capture?("Edit")).to be true
    end
  end
end
