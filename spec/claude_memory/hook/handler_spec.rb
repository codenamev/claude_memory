# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "digest"

RSpec.describe ClaudeMemory::Hook::Handler do
  let(:db_path) { File.join(Dir.tmpdir, "hook_handler_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:handler) { described_class.new(store) }
  let(:transcript_path) { File.join(Dir.tmpdir, "hook_transcript_#{Process.pid}.jsonl") }

  before { File.write(transcript_path, "test content\n") }

  after do
    store.close
    FileUtils.rm_f(db_path)
    FileUtils.rm_f(transcript_path)
  end

  describe "#ingest" do
    let(:payload) do
      {
        "hook_type" => "Stop",
        "session_id" => "session-123",
        "transcript_path" => transcript_path
      }
    end

    it "ingests from hook payload" do
      result = handler.ingest(payload)

      expect(result[:status]).to eq(:ingested)
      expect(result[:bytes_read]).to eq(13)
    end

    it "returns no_change when already ingested" do
      handler.ingest(payload)
      result = handler.ingest(payload)

      # With incremental sync, unchanged files are skipped
      expect(result[:status]).to eq(:skipped)
    end

    it "raises for missing session_id" do
      payload.delete("session_id")

      expect { handler.ingest(payload) }.to raise_error(
        ClaudeMemory::Hook::Handler::PayloadError,
        /session_id/
      )
    end

    it "raises for missing transcript_path" do
      payload.delete("transcript_path")

      expect { handler.ingest(payload) }.to raise_error(
        ClaudeMemory::Hook::Handler::PayloadError,
        /transcript_path/
      )
    end

    it "returns skipped status when transcript file doesn't exist" do
      payload["transcript_path"] = "/nonexistent/transcript.jsonl"

      result = handler.ingest(payload)

      expect(result[:status]).to eq(:skipped)
      expect(result[:reason]).to eq("transcript_not_found")
      expect(result[:message]).to include("/nonexistent/transcript.jsonl")
    end

    context "with environment variable fallback" do
      let(:env) do
        {
          "CLAUDE_SESSION_ID" => "env-session-456",
          "CLAUDE_TRANSCRIPT_PATH" => transcript_path
        }
      end
      let(:handler) { described_class.new(store, env: env) }

      it "uses env vars when payload fields are missing" do
        result = handler.ingest({})

        expect(result[:status]).to eq(:ingested)
      end

      it "prefers payload over env vars" do
        result = handler.ingest({"session_id" => "payload-session"})

        expect(result[:status]).to eq(:ingested)
      end
    end
  end

  describe "#sweep" do
    let(:payload) do
      {
        "hook_type" => "Notification",
        "budget" => 5
      }
    end

    it "runs sweep with budget from payload" do
      result = handler.sweep(payload)

      expect(result[:stats]).to include(:elapsed_seconds)
      expect(result[:stats][:budget_honored]).to be true
    end

    it "uses default budget when not specified" do
      payload.delete("budget")
      result = handler.sweep(payload)

      expect(result[:stats]).to include(:elapsed_seconds)
    end
  end

  describe "#publish" do
    let(:project_dir) { Dir.mktmpdir("hook_publish_#{Process.pid}") }
    let(:original_dir) { Dir.pwd }
    let(:payload) do
      {
        "hook_type" => "SessionEnd",
        "mode" => "shared"
      }
    end

    before do
      @original_dir = Dir.pwd
      Dir.chdir(project_dir)
    end

    after do
      Dir.chdir(@original_dir)
      FileUtils.rm_rf(project_dir)
    end

    it "publishes snapshot" do
      result = handler.publish(payload)

      expect([:updated, :unchanged]).to include(result[:status])
      expect(result[:path]).to include("claude_memory.generated.md")
    end

    it "respects mode from payload" do
      payload["mode"] = "local"
      result = handler.publish(payload)

      expect(result[:path]).to include("local")
    end
  end

  describe "#context" do
    let(:tmpdir) { Dir.mktmpdir("hook_context_#{Process.pid}") }
    let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
    let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }

    let(:manager) do
      ClaudeMemory::Store::StoreManager.new(
        global_db_path: global_db_path,
        project_db_path: project_db_path,
        project_path: tmpdir
      )
    end

    let(:handler_with_manager) { described_class.new(store, manager: manager) }
    let(:payload) { {"hook_event_name" => "SessionStart"} }

    after do
      manager.close
      FileUtils.rm_rf(tmpdir)
    end

    it "returns ok status" do
      result = handler_with_manager.context(payload)
      expect(result[:status]).to eq(:ok)
    end

    it "returns nil context when no facts exist" do
      result = handler_with_manager.context(payload)
      expect(result[:context]).to be_nil
    end

    it "returns context with facts when they exist" do
      manager.ensure_both!
      project_store = manager.project_store

      text = "decision constraint Use Redis for caching"
      content_id = project_store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize,
        raw_text: text
      )
      fts = ClaudeMemory::Index::LexicalFTS.new(project_store)
      fts.index_content_item(content_id, text)
      entity_id = project_store.find_or_create_entity(type: "repo", name: "myapp")
      fact_id = project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "decision",
        object_literal: "Use Redis for caching",
        status: "active",
        scope: "project",
        project_path: tmpdir
      )
      project_store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: text,
        strength: "stated"
      )

      result = handler_with_manager.context(payload)
      expect(result[:status]).to eq(:ok)
      expect(result[:context]).to include("Redis")
    end
  end
end
