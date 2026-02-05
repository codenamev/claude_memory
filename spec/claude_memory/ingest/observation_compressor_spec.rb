# frozen_string_literal: true

require "json"

RSpec.describe ClaudeMemory::Ingest::ObservationCompressor do
  let(:compressor) { described_class.new }

  describe "#compress" do
    context "Edit tool" do
      it "compresses edit with old and new strings" do
        input = JSON.generate(
          "file_path" => "/src/auth.rb",
          "old_string" => "def login",
          "new_string" => "def async_login"
        )
        result = compressor.compress("Edit", input)

        expect(result).to eq("Edited auth.rb: 'def login' → 'def async_login'")
      end

      it "truncates long strings" do
        input = JSON.generate(
          "file_path" => "/src/very_long_method.rb",
          "old_string" => "a" * 100,
          "new_string" => "b" * 100
        )
        result = compressor.compress("Edit", input)

        expect(result).to include("Edited very_long_method.rb")
        expect(result).to include("→")
        expect(result.length).to be <= described_class::MAX_SUMMARY_LENGTH + 3
      end
    end

    context "Write tool" do
      it "compresses write with file name and size" do
        input = JSON.generate(
          "file_path" => "/config/database.yml",
          "content" => "production:\n  adapter: postgresql\n  database: myapp"
        )
        result = compressor.compress("Write", input)

        expect(result).to match(/Created database\.yml \(\d+ chars\)/)
      end
    end

    context "Bash tool" do
      it "compresses bash with command" do
        input = JSON.generate("command" => "npm test")
        result = compressor.compress("Bash", input)

        expect(result).to eq("Ran: npm test")
      end

      it "uses description when available" do
        input = JSON.generate(
          "command" => "npm run build:production -- --verbose",
          "description" => "Build for production"
        )
        result = compressor.compress("Bash", input)

        expect(result).to eq("Ran: Build for production")
      end

      it "truncates long commands" do
        input = JSON.generate("command" => "a" * 200)
        result = compressor.compress("Bash", input)

        expect(result.length).to be <= described_class::MAX_SUMMARY_LENGTH + 3
      end
    end

    context "Read tool" do
      it "compresses read with file name" do
        input = JSON.generate("file_path" => "/src/models/user.rb")
        result = compressor.compress("Read", input)

        expect(result).to eq("Read user.rb")
      end

      it "includes line range when offset and limit are provided" do
        input = JSON.generate(
          "file_path" => "/src/models/user.rb",
          "offset" => 10,
          "limit" => 50
        )
        result = compressor.compress("Read", input)

        expect(result).to eq("Read user.rb lines 10-60")
      end
    end

    context "Glob tool" do
      it "compresses glob with pattern" do
        input = JSON.generate("pattern" => "**/*.rb")
        result = compressor.compress("Glob", input)

        expect(result).to eq("Glob **/*.rb")
      end

      it "includes path when provided" do
        input = JSON.generate("pattern" => "*.ts", "path" => "/src/components")
        result = compressor.compress("Glob", input)

        expect(result).to eq("Glob *.ts in components")
      end
    end

    context "Grep tool" do
      it "compresses grep with pattern" do
        input = JSON.generate("pattern" => "TODO.*fix")
        result = compressor.compress("Grep", input)

        expect(result).to eq("Searched 'TODO.*fix'")
      end

      it "includes path when provided" do
        input = JSON.generate("pattern" => "TODO", "path" => "/src")
        result = compressor.compress("Grep", input)

        expect(result).to eq("Searched 'TODO' in src")
      end
    end

    context "Task tool" do
      it "compresses task with description and agent type" do
        input = JSON.generate(
          "description" => "Find API endpoints",
          "subagent_type" => "Explore"
        )
        result = compressor.compress("Task", input)

        expect(result).to eq("Spawned Explore: Find API endpoints")
      end
    end

    context "WebFetch tool" do
      it "compresses web fetch with URL" do
        input = JSON.generate("url" => "https://example.com/api/docs")
        result = compressor.compress("WebFetch", input)

        expect(result).to eq("Fetched https://example.com/api/docs")
      end
    end

    context "WebSearch tool" do
      it "compresses web search with query" do
        input = JSON.generate("query" => "ruby sqlite performance")
        result = compressor.compress("WebSearch", input)

        expect(result).to eq("Searched web: 'ruby sqlite performance'")
      end
    end

    context "NotebookEdit tool" do
      it "compresses notebook edit" do
        input = JSON.generate(
          "notebook_path" => "/notebooks/analysis.ipynb",
          "edit_mode" => "insert",
          "new_source" => "import pandas as pd"
        )
        result = compressor.compress("NotebookEdit", input)

        expect(result).to eq("Notebook insert in analysis.ipynb")
      end
    end

    context "unknown tools" do
      it "falls back to generic format" do
        input = JSON.generate("foo" => "bar", "baz" => "qux")
        result = compressor.compress("CustomTool", input)

        expect(result).to eq("CustomTool(foo, baz)")
      end
    end

    context "edge cases" do
      it "returns nil for nil input" do
        expect(compressor.compress("Edit", nil)).to be_nil
      end

      it "returns nil for empty input" do
        expect(compressor.compress("Edit", "")).to be_nil
      end

      it "returns nil for invalid JSON" do
        expect(compressor.compress("Edit", "not json")).to be_nil
      end
    end
  end
end
