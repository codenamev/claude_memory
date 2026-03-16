# frozen_string_literal: true

require "tmpdir"

RSpec.describe ClaudeMemory::MCP::Tools, "error handling" do
  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      Dir.chdir(tmpdir) do
        ENV["HOME"] = tmpdir
        example.run
        ENV.delete("HOME")
      end
    end
  end

  describe "when databases don't exist" do
    it "returns benign response for memory.recall when not initialized" do
      db_path = File.join(@tmpdir, "nonexistent.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      # Close and delete the database to simulate missing db
      store.close
      File.delete(db_path) if File.exist?(db_path)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result[:severity]).to eq("benign")
      expect(result[:message]).to match(/not yet initialized/)
    end

    it "includes tool name in response" do
      db_path = File.join(@tmpdir, "nonexistent.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      store.close
      File.delete(db_path) if File.exist?(db_path)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result[:tool]).to eq("recall")
    end

    it "returns empty results array for benign response" do
      db_path = File.join(@tmpdir, "nonexistent.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      store.close
      File.delete(db_path) if File.exist?(db_path)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result[:results]).to eq([])
    end
  end

  describe "when databases exist" do
    it "returns normal results for memory.recall" do
      db_path = File.join(@tmpdir, "test.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result).to have_key(:facts)
      expect(result).not_to have_key(:error)
      expect(result[:facts]).to be_an(Array)

      store.close
    end
  end
end
