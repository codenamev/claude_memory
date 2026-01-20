# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Ingest::Ingester do
  let(:db_path) { File.join(Dir.tmpdir, "ingester_test_#{Process.pid}.sqlite3") }
  let(:transcript_path) { File.join(Dir.tmpdir, "transcript_#{Process.pid}.jsonl") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:ingester) { described_class.new(store) }

  before { File.write(transcript_path, "") }

  after do
    store.close
    FileUtils.rm_f(db_path)
    FileUtils.rm_f(transcript_path)
  end

  describe "#ingest" do
    it "returns no_change for empty transcript" do
      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)
      expect(result[:status]).to eq(:no_change)
      expect(result[:bytes_read]).to eq(0)
    end

    it "ingests new content and updates cursor" do
      File.write(transcript_path, "first chunk\n")
      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      expect(result[:status]).to eq(:ingested)
      expect(result[:bytes_read]).to eq(12)
      expect(result[:content_id]).to be > 0

      cursor = store.get_delta_cursor("sess-1", transcript_path)
      expect(cursor).to eq(12)
    end

    it "ingests only delta on subsequent calls" do
      File.write(transcript_path, "first\n")
      ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      File.write(transcript_path, "first\nsecond\n")
      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      expect(result[:status]).to eq(:ingested)
      expect(result[:bytes_read]).to eq(7)
    end

    it "returns no_change when no new content" do
      File.write(transcript_path, "content\n")
      ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)
      expect(result[:status]).to eq(:no_change)
    end

    it "handles file shrinking (compaction)" do
      File.write(transcript_path, "very long content\n")
      ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      File.write(transcript_path, "short\n")
      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      expect(result[:status]).to eq(:ingested)
      expect(result[:bytes_read]).to eq(6)
    end

    it "is idempotent for same content" do
      File.write(transcript_path, "content\n")
      result1 = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)
      id1 = result1[:content_id]

      store.update_delta_cursor("sess-1", transcript_path, 0)

      result2 = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)
      expect(result2[:content_id]).to eq(id1)
    end

    context "project scoping" do
      it "stores project_path from explicit parameter" do
        File.write(transcript_path, "content\n")
        result = ingester.ingest(
          source: "claude_code",
          session_id: "sess-1",
          transcript_path: transcript_path,
          project_path: "/path/to/my-project"
        )

        expect(result[:project_path]).to eq("/path/to/my-project")

        row = store.content_items.where(id: result[:content_id]).first
        expect(row[:project_path]).to eq("/path/to/my-project")
      end

      it "detects project_path from CLAUDE_PROJECT_DIR env var" do
        env = {"CLAUDE_PROJECT_DIR" => "/env/project/path"}
        ingester_with_env = described_class.new(store, env: env)

        File.write(transcript_path, "content\n")
        result = ingester_with_env.ingest(
          source: "claude_code",
          session_id: "sess-1",
          transcript_path: transcript_path
        )

        expect(result[:project_path]).to eq("/env/project/path")
      end

      it "falls back to Dir.pwd when no env var" do
        env = {}
        ingester_with_env = described_class.new(store, env: env)

        File.write(transcript_path, "content\n")
        result = ingester_with_env.ingest(
          source: "claude_code",
          session_id: "sess-1",
          transcript_path: transcript_path
        )

        expect(result[:project_path]).to eq(Dir.pwd)
      end
    end
  end
end
