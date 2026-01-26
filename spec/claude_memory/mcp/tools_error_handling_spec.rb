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
    it "returns helpful error for memory.recall" do
      # Try to create tools with non-existent database path
      db_path = File.join(@tmpdir, "nonexistent.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      # Close and delete the database to simulate missing db
      store.close
      File.delete(db_path) if File.exist?(db_path)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result).to have_key(:error)
      expect(result[:error]).to match(/Database not found/)
      expect(result[:message]).to match(/Run memory.check_setup/)
      expect(result[:recommendations]).to be_an(Array)
      expect(result[:recommendations]).to include(match(/claude-memory init/))
    end

    it "includes actionable recommendations" do
      db_path = File.join(@tmpdir, "nonexistent.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      store.close
      File.delete(db_path) if File.exist?(db_path)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result[:recommendations]).to include("Run memory.check_setup to diagnose the issue")
      expect(result[:recommendations]).to include("If not initialized, run: claude-memory init")
      expect(result[:recommendations]).to include("For help: claude-memory doctor")
    end

    it "provides error details" do
      db_path = File.join(@tmpdir, "nonexistent.db")
      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      tools = described_class.new(store)

      store.close
      File.delete(db_path) if File.exist?(db_path)

      result = tools.call("memory.recall", {"query" => "test"})

      expect(result).to have_key(:details)
      expect(result[:details]).to be_a(String)
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
