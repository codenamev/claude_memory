# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Ingest::ToolExtractor do
  subject(:extractor) { described_class.new }

  describe "#extract" do
    it "extracts tool_use blocks from assistant messages" do
      raw_text = <<~JSONL
        {"type": "assistant", "timestamp": "2026-03-19T12:00:00Z", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"path": "/tmp/test.rb"}}]}}
      JSONL

      tools = extractor.extract(raw_text)
      expect(tools.size).to eq(1)
      expect(tools.first[:tool_name]).to eq("Read")
      expect(tools.first[:timestamp]).to eq("2026-03-19T12:00:00Z")
      expect(tools.first[:is_error]).to be false
    end

    it "extracts multiple tool calls from one message" do
      content = [
        {"type" => "tool_use", "name" => "Read", "input" => {"path" => "a.rb"}},
        {"type" => "text", "text" => "some text"},
        {"type" => "tool_use", "name" => "Edit", "input" => {"path" => "b.rb"}}
      ]
      raw_text = {type: "assistant", message: {content: content}}.to_json + "\n"

      tools = extractor.extract(raw_text)
      expect(tools.size).to eq(2)
      expect(tools.map { |t| t[:tool_name] }).to eq(["Read", "Edit"])
    end

    it "skips non-assistant messages" do
      raw_text = <<~JSONL
        {"type": "system", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {}}]}}
      JSONL

      expect(extractor.extract(raw_text)).to eq([])
    end

    it "returns empty array for nil input" do
      expect(extractor.extract(nil)).to eq([])
    end

    it "returns empty array for empty input" do
      expect(extractor.extract("")).to eq([])
    end

    it "handles invalid JSON lines gracefully" do
      raw_text = "not json\n{also broken\n"
      expect(extractor.extract(raw_text)).to eq([])
    end

    it "truncates large tool inputs" do
      large_input = {"data" => "x" * 2000}
      content = [{"type" => "tool_use", "name" => "Write", "input" => large_input}]
      raw_text = {type: "assistant", message: {content: content}}.to_json + "\n"

      tools = extractor.extract(raw_text)
      expect(tools.first[:tool_input].length).to be <= 1003 # 1000 + "..."
    end
  end
end
