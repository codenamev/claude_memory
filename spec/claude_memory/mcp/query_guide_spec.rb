# frozen_string_literal: true

require "spec_helper"
require "claude_memory/mcp/query_guide"

RSpec.describe ClaudeMemory::MCP::QueryGuide do
  describe ".definition" do
    it "returns prompt name and description" do
      defn = described_class.definition

      expect(defn[:name]).to eq("memory_guide")
      expect(defn[:description]).to be_a(String)
      expect(defn[:description]).not_to be_empty
    end
  end

  describe ".content" do
    it "returns messages array with user role" do
      content = described_class.content

      expect(content[:messages]).to be_an(Array)
      expect(content[:messages].size).to eq(1)
      expect(content[:messages][0][:role]).to eq("user")
    end

    it "includes text content type" do
      msg = described_class.content[:messages][0]

      expect(msg[:content][:type]).to eq("text")
      expect(msg[:content][:text]).to be_a(String)
    end

    it "mentions key tools in guide text" do
      text = described_class.content[:messages][0][:content][:text]

      expect(text).to include("memory.recall")
      expect(text).to include("memory.recall_semantic")
      expect(text).to include("memory.search_concepts")
      expect(text).to include("memory.recall_index")
      expect(text).to include("memory.decisions")
      expect(text).to include("memory.conventions")
    end

    it "includes score interpretation" do
      text = described_class.content[:messages][0][:content][:text]

      expect(text).to include("Score Interpretation")
      expect(text).to include("0.85")
    end

    it "includes scope documentation" do
      text = described_class.content[:messages][0][:content][:text]

      expect(text).to include("global")
      expect(text).to include("project")
    end
  end
end
