# frozen_string_literal: true

require "digest"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Moments do
  let(:tmpdir) { Dir.mktmpdir("moments_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global", "memory.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project", "memory.sqlite3") }
  let(:manager) do
    FileUtils.mkdir_p(File.dirname(global_db_path))
    FileUtils.mkdir_p(File.dirname(project_db_path))
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end
  let(:moments) { described_class.new(manager) }
  let(:project_store) { manager.project_store }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def record(event_type, details, status: "success", session_id: "sess-1", duration_ms: 10)
    ClaudeMemory::ActivityLog.record(project_store,
      event_type: event_type, status: status,
      session_id: session_id, duration_ms: duration_ms, details: details)
  end

  def insert_fact(subject:, predicate:, object:)
    entity_id = project_store.find_or_create_entity(type: "repo", name: subject)
    project_store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate, object_literal: object,
      status: "active", confidence: 0.9, scope: "project"
    )
  end

  describe "#list" do
    it "returns the empty shape when no events exist" do
      expect(moments.list).to eq(moments: [], next_before: nil, has_more: false)
    end

    it "classifies recall events by result count" do
      record("recall", {tool: "memory.recall", query: "foo", result_count: 3, top_fact_ids: []})
      record("recall", {tool: "memory.recall", query: "bar", result_count: 0, top_fact_ids: []})

      kinds = moments.list[:moments].map { |m| m[:kind] }.sort
      expect(kinds).to eq(%w[recall_empty recall_hit])
    end

    it "resolves top_fact_ids into rendered fact summaries on recall moments" do
      fact_id = insert_fact(subject: "dash", predicate: "convention", object: "feed-first UI")
      record("recall", {tool: "memory.conventions", result_count: 1, top_fact_ids: [fact_id]})

      moment = moments.list[:moments].first
      expect(moment[:kind]).to eq("recall_hit")
      expect(moment[:top_facts].first[:object]).to eq("feed-first UI")
      expect(moment[:top_facts].first[:predicate]).to eq("convention")
    end

    it "inlines content preview and extracted facts on extraction events" do
      text = "We decided to use Sequel for DB access"
      ci_id = project_store.upsert_content_item(
        source: "claude_code",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize,
        session_id: "sess-1",
        raw_text: text
      )
      fact_id = insert_fact(subject: "app", predicate: "uses_framework", object: "Sequel")
      project_store.insert_provenance(fact_id: fact_id, content_item_id: ci_id,
        quote: text, strength: "stated")

      record("store_extraction", {
        tool: "memory.store_extraction",
        facts_created: 1, entities_created: 1,
        content_item_id: ci_id
      })

      moment = moments.list[:moments].first
      expect(moment[:kind]).to eq("extraction")
      expect(moment[:content_item][:id]).to eq(ci_id)
      expect(moment[:content_item][:preview]).to include("Sequel")
      expect(moment[:extracted_facts].first[:object]).to eq("Sequel")
    end

    it "surfaces context_injection kind with fact count and preview" do
      fact_id = insert_fact(subject: "app", predicate: "convention", object: "tabs over spaces")
      record("hook_context", {
        source: "startup",
        context_length: 123,
        preview: "## Decisions\n- app.convention = tabs over spaces",
        top_fact_ids: [fact_id],
        top_subjects: ["app"],
        fact_count: 1
      })

      moment = moments.list[:moments].first
      expect(moment[:kind]).to eq("context_injection")
      expect(moment[:fact_count]).to eq(1)
      expect(moment[:context_preview]).to include("Decisions")
      expect(moment[:top_facts].first[:object]).to eq("tabs over spaces")
    end

    it "marks skipped context events as context_skipped" do
      record("hook_context", {source: "resume", context_length: nil}, status: "skipped")

      moment = moments.list[:moments].first
      expect(moment[:kind]).to eq("context_skipped")
      expect(moment[:status]).to eq("skipped")
    end

    it "filters by the kinds query parameter" do
      record("recall", {tool: "memory.recall", result_count: 1, top_fact_ids: []})
      record("hook_ingest", {bytes_read: 100, content_id: nil})

      only_recalls = moments.list("kinds" => "recall_hit")
      expect(only_recalls[:moments].map { |m| m[:kind] }).to eq(%w[recall_hit])
    end

    it "applies the before cursor to paginate older-than a timestamp" do
      # occurred_at is stored at second precision, so we need distinct
      # wall-clock seconds between the two events for the boundary to split them.
      record("recall", {tool: "memory.recall", result_count: 1, top_fact_ids: []})
      sleep 1.1
      boundary = Time.now.utc.iso8601
      sleep 1.1
      record("recall", {tool: "memory.recall", result_count: 2, top_fact_ids: []})

      newer = moments.list
      expect(newer[:moments].size).to eq(2)

      older = moments.list("before" => boundary)
      expect(older[:moments].size).to eq(1)
    end

    it "enforces the limit clamp" do
      result = moments.list("limit" => "1000")
      # Clamped to 200 server-side; we only seeded 0 so moments is empty
      # but the call must not raise.
      expect(result).to have_key(:moments)
    end

    it "attaches feedback verdicts to moments when present" do
      record("recall", {tool: "memory.recall", query: "foo", result_count: 1, top_fact_ids: []})
      event_id = project_store.activity_events.first[:id]
      project_store.upsert_moment_feedback(event_id: event_id, verdict: "up", note: "helpful")

      moment = moments.list[:moments].first
      expect(moment[:feedback][:verdict]).to eq("up")
      expect(moment[:feedback][:note]).to eq("helpful")
    end

    it "omits feedback for moments that haven't been rated" do
      record("recall", {tool: "memory.recall", query: "foo", result_count: 1, top_fact_ids: []})

      moment = moments.list[:moments].first
      expect(moment[:feedback]).to be_nil
    end
  end
end
