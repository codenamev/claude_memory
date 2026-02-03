# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/snippet_extractor"

RSpec.describe ClaudeMemory::Core::SnippetExtractor do
  describe ".extract" do
    let(:content) do
      <<~TEXT
        Line one about setup
        Line two about configuration
        Line three about database PostgreSQL
        Line four about migrations
        Line five about testing
        Line six about deployment
      TEXT
    end

    it "finds the line with most query term matches" do
      snippet = described_class.extract(content, "database PostgreSQL")

      expect(snippet).to include("database PostgreSQL")
    end

    it "includes context lines (1 before + 2 after)" do
      snippet = described_class.extract(content, "database PostgreSQL")

      expect(snippet).to include("configuration")  # 1 line before
      expect(snippet).to include("migrations")      # 1 line after
      expect(snippet).to include("testing")          # 2 lines after
    end

    it "handles query at the first line" do
      snippet = described_class.extract(content, "setup")

      expect(snippet).to include("setup")
      expect(snippet).to include("configuration") # line after
      expect(snippet).to include("database")       # 2 lines after
    end

    it "handles query at the last line" do
      snippet = described_class.extract(content, "deployment")

      expect(snippet).to include("testing")     # 1 line before
      expect(snippet).to include("deployment")
    end

    it "returns nil for nil content" do
      expect(described_class.extract(nil, "test")).to be_nil
    end

    it "returns nil for empty content" do
      expect(described_class.extract("", "test")).to be_nil
    end

    it "returns nil for nil query" do
      expect(described_class.extract(content, nil)).to be_nil
    end

    it "returns nil for empty query" do
      expect(described_class.extract(content, "")).to be_nil
    end

    it "ignores single-character query terms" do
      expect(described_class.extract(content, "a")).to be_nil
    end

    it "is case-insensitive" do
      snippet = described_class.extract(content, "POSTGRESQL")

      expect(snippet).to include("PostgreSQL")
    end

    it "truncates long snippets" do
      long_line = "x" * 600
      long_content = "line before\n#{long_line}\nline after"

      snippet = described_class.extract(long_content, "xxxxxxxx")

      expect(snippet.length).to be <= 500
      expect(snippet).to end_with("...")
    end
  end

  describe ".extract_with_lines" do
    let(:content) do
      <<~TEXT
        Line one
        Line two
        Line three about database
        Line four about migrations
        Line five about testing
      TEXT
    end

    it "returns snippet with line range" do
      result = described_class.extract_with_lines(content, "database")

      expect(result).to be_a(Hash)
      expect(result[:snippet]).to include("database")
      expect(result[:line_start]).to eq(2)  # 1 before line 3
      expect(result[:line_end]).to eq(5)    # 2 after line 3
    end

    it "uses 1-indexed line numbers" do
      result = described_class.extract_with_lines(content, "Line one")

      expect(result[:line_start]).to eq(1)
    end

    it "returns nil for nil inputs" do
      expect(described_class.extract_with_lines(nil, "test")).to be_nil
      expect(described_class.extract_with_lines(content, nil)).to be_nil
    end
  end

  describe ".tokenize_query" do
    it "splits on whitespace" do
      expect(described_class.tokenize_query("hello world")).to eq(["hello", "world"])
    end

    it "downcases terms" do
      expect(described_class.tokenize_query("Hello World")).to eq(["hello", "world"])
    end

    it "rejects single-character terms" do
      expect(described_class.tokenize_query("a bb c dd")).to eq(["bb", "dd"])
    end
  end

  describe ".find_best_line" do
    it "returns index of line with most term matches" do
      lines = ["no match", "one term", "both term match"]
      terms = ["both", "term", "match"]

      expect(described_class.find_best_line(lines, terms)).to eq(2)
    end

    it "returns first match on tie" do
      lines = ["one match", "one other"]
      terms = ["one"]

      expect(described_class.find_best_line(lines, terms)).to eq(0)
    end

    it "returns nil when no terms match" do
      lines = ["hello", "world"]
      terms = ["xyz"]

      expect(described_class.find_best_line(lines, terms)).to be_nil
    end
  end
end
