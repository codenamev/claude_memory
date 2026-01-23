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

      sleep 1.01  # Ensure mtime changes (filesystem has 1-second resolution)
      File.write(transcript_path, "first\nsecond\n")
      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      expect(result[:status]).to eq(:ingested)
      expect(result[:bytes_read]).to eq(7)
    end

    it "returns no_change when no new content" do
      File.write(transcript_path, "content\n")
      ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      result = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)
      # With incremental sync, unchanged files are skipped based on mtime
      expect(result[:status]).to eq(:skipped)
      expect(result[:reason]).to eq("unchanged")
    end

    it "handles file shrinking (compaction)" do
      File.write(transcript_path, "very long content\n")
      ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      sleep 1.01  # Ensure mtime changes (filesystem has 1-second resolution)
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

      # Touch the file to update mtime (must wait long enough for filesystem to register change)
      sleep 1.01
      FileUtils.touch(transcript_path)

      # With incremental sync + mtime changed, should re-ingest from cursor position
      result2 = ingester.ingest(source: "claude_code", session_id: "sess-1", transcript_path: transcript_path)

      # Should get the same content_id back (content deduplication)
      expect(result2[:status]).to eq(:ingested)
      expect(result2[:content_id]).to eq(id1)
    end

    context "privacy tag stripping" do
      it "strips private tags from ingested content" do
        File.write(transcript_path, "Public <private>Secret API key</private> Public")

        result = ingester.ingest(
          source: "test",
          session_id: "sess-123",
          transcript_path: transcript_path
        )

        item = store.content_items.where(id: result[:content_id]).first
        expect(item[:raw_text]).to eq("Public  Public")
        expect(item[:raw_text]).not_to include("Secret API key")
      end

      it "strips multiple privacy tag types" do
        File.write(transcript_path, "A <private>X</private> B <no-memory>Y</no-memory> C <secret>Z</secret> D")

        result = ingester.ingest(
          source: "test",
          session_id: "sess-123",
          transcript_path: transcript_path
        )

        item = store.content_items.where(id: result[:content_id]).first
        expect(item[:raw_text]).to eq("A  B  C  D")
        expect(item[:raw_text]).not_to include("X")
        expect(item[:raw_text]).not_to include("Y")
        expect(item[:raw_text]).not_to include("Z")
      end

      it "strips claude-memory-context system tags" do
        File.write(transcript_path, "New <claude-memory-context>Old context</claude-memory-context> Content")

        result = ingester.ingest(
          source: "test",
          session_id: "sess-123",
          transcript_path: transcript_path
        )

        item = store.content_items.where(id: result[:content_id]).first
        expect(item[:raw_text]).to eq("New  Content")
        expect(item[:raw_text]).not_to include("Old context")
      end

      it "preserves content without privacy tags" do
        File.write(transcript_path, "No privacy tags in this content")

        result = ingester.ingest(
          source: "test",
          session_id: "sess-123",
          transcript_path: transcript_path
        )

        item = store.content_items.where(id: result[:content_id]).first
        expect(item[:raw_text]).to eq("No privacy tags in this content")
      end

      it "handles multiline private content" do
        content = <<~TEXT
          Config:
          <private>
          API_KEY=secret123
          PASSWORD=pass456
          </private>
          Public config
        TEXT

        File.write(transcript_path, content)

        result = ingester.ingest(
          source: "test",
          session_id: "sess-123",
          transcript_path: transcript_path
        )

        item = store.content_items.where(id: result[:content_id]).first
        expect(item[:raw_text]).not_to include("API_KEY")
        expect(item[:raw_text]).not_to include("secret123")
        expect(item[:raw_text]).to include("Public config")
      end
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
