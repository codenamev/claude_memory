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

    it "records context_tokens on the activity event when context is emitted" do
      manager.ensure_both!
      project_store = manager.project_store

      text = "decision constraint Use Redis for caching"
      content_id = project_store.upsert_content_item(
        source: "test", session_id: "sess-1",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize, raw_text: text
      )
      ClaudeMemory::Index::LexicalFTS.new(project_store).index_content_item(content_id, text)
      entity_id = project_store.find_or_create_entity(type: "repo", name: "myapp")
      fact_id = project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "decision",
        object_literal: "Use Redis for caching",
        status: "active", scope: "project", project_path: tmpdir
      )
      project_store.insert_provenance(
        fact_id: fact_id, content_item_id: content_id,
        quote: text, strength: "stated"
      )

      result = handler_with_manager.context(payload)
      expect(result[:context]).not_to be_nil

      event = store.activity_events.where(event_type: "hook_context").order(:id).last
      details = JSON.parse(event[:detail_json])
      expected_tokens = ClaudeMemory::Core::TokenEstimator.estimate(result[:context])
      expect(details["context_tokens"]).to eq(expected_tokens)
      expect(details["context_tokens"]).to be > 0
    end
  end

  describe "#nudge" do
    let(:tmpdir) { Dir.mktmpdir("hook_nudge_#{Process.pid}") }
    let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
    let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
    let(:manager) do
      ClaudeMemory::Store::StoreManager.new(
        global_db_path: global_db_path,
        project_db_path: project_db_path,
        project_path: tmpdir
      )
    end
    let(:project_store) { manager.project_store }
    let(:env) { {} }
    let(:handler) { described_class.new(project_store, manager: manager, env: env) }
    let(:session_id) { "sess-nudge-1" }

    before { manager.ensure_both! }
    after do
      manager.close
      FileUtils.rm_rf(tmpdir)
    end

    def seed_session_fact(used_in_recall: false)
      text = "fact body #{rand(1_000_000)}"
      content_id = project_store.upsert_content_item(
        source: "claude_code", session_id: session_id,
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize, raw_text: text
      )
      entity_id = project_store.find_or_create_entity(type: "repo", name: "app")
      fact_id = project_store.insert_fact(
        subject_entity_id: entity_id, predicate: "convention",
        object_literal: text, status: "active", scope: "project"
      )
      project_store.insert_provenance(fact_id: fact_id, content_item_id: content_id, quote: text)

      if used_in_recall
        ClaudeMemory::ActivityLog.record(project_store,
          event_type: "recall", status: "success",
          session_id: session_id, duration_ms: 5,
          details: {top_fact_ids: [fact_id], result_count: 1})
      end

      fact_id
    end

    it "returns silent when CLAUDE_MEMORY_NO_NUDGE=1" do
      env["CLAUDE_MEMORY_NO_NUDGE"] = "1"
      seed_session_fact
      result = handler.nudge({"session_id" => session_id})
      expect(result[:status]).to eq(:silent)
      expect(result[:reason]).to eq("opt_out")
    end

    it "returns silent when payload has no session_id" do
      result = handler.nudge({})
      expect(result[:status]).to eq(:silent)
      expect(result[:reason]).to eq("no_session_id")
    end

    it "returns silent when memory contributed nothing this session" do
      result = handler.nudge({"session_id" => session_id})
      expect(result[:status]).to eq(:silent)
      expect(result[:reason]).to eq("no_contributions")
    end

    it "emits a nudge with N facts and 0% used when nothing was used" do
      seed_session_fact
      seed_session_fact

      result = handler.nudge({"session_id" => session_id})
      expect(result[:status]).to eq(:emitted)
      expect(result[:n]).to eq(2)
      expect(result[:used]).to eq(0)
      expect(result[:pct]).to eq(0)
      expect(result[:message]).to eq("memory contributed 2 facts this session, %used = 0%")
    end

    it "computes %used from top_fact_ids in same-session activity events" do
      seed_session_fact(used_in_recall: true)
      seed_session_fact(used_in_recall: true)
      seed_session_fact

      result = handler.nudge({"session_id" => session_id})
      expect(result[:n]).to eq(3)
      expect(result[:used]).to eq(2)
      expect(result[:pct]).to eq(67)
    end

    it "uses singular wording for n=1" do
      seed_session_fact
      result = handler.nudge({"session_id" => session_id})
      expect(result[:message]).to start_with("memory contributed 1 fact ")
    end

    it "records a roi_nudge activity event when emitting" do
      seed_session_fact
      handler.nudge({"session_id" => session_id})

      event = project_store.activity_events.where(event_type: "roi_nudge").order(:id).last
      expect(event).not_to be_nil
      expect(event[:status]).to eq("success")
      expect(event[:session_id]).to eq(session_id)
      details = JSON.parse(event[:detail_json])
      expect(details["n"]).to eq(1)
    end

    it "quiets after MAX_NUDGES prior nudges" do
      # Pre-seed 10 prior nudge events
      described_class::MAX_NUDGES.times do |i|
        ClaudeMemory::ActivityLog.record(project_store,
          event_type: "roi_nudge", status: "success",
          session_id: "sess-prior-#{i}", duration_ms: 1, details: {n: 1})
      end

      seed_session_fact
      result = handler.nudge({"session_id" => session_id})

      expect(result[:status]).to eq(:silent)
      expect(result[:reason]).to eq("first_week_complete")
      expect(result[:prior_count]).to eq(described_class::MAX_NUDGES)
    end

    it "still emits on the MAX_NUDGES-th call (counting from zero)" do
      # 9 prior nudges leaves room for one more
      (described_class::MAX_NUDGES - 1).times do |i|
        ClaudeMemory::ActivityLog.record(project_store,
          event_type: "roi_nudge", status: "success",
          session_id: "sess-prior-#{i}", duration_ms: 1, details: {n: 1})
      end

      seed_session_fact
      result = handler.nudge({"session_id" => session_id})

      expect(result[:status]).to eq(:emitted)
      expect(result[:remaining]).to eq(0)
    end
  end
end
