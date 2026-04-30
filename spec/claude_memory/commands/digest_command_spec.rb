# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"
require "json"

RSpec.describe ClaudeMemory::Commands::DigestCommand do
  let(:tmpdir) { Dir.mktmpdir("digest_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
    )
  end

  before do
    manager.ensure_both!
    allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(manager)
  end

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def record_event(store, event_type, details = {}, status: "success")
    ClaudeMemory::ActivityLog.record(store,
      event_type: event_type, status: status,
      session_id: "sess-1", duration_ms: 10, details: details)
  end

  def create_fact(store, predicate:, object:, scope: "project")
    entity_id = store.find_or_create_entity(type: "repo", name: "app")
    store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate,
      object_literal: object, status: "active", scope: scope, confidence: 0.9
    )
  end

  describe "#call" do
    it "renders a baseline report on an empty database" do
      expect(command.call([])).to eq(0)

      out = stdout.string
      expect(out).to include("# ClaudeMemory Digest")
      expect(out).to include("## Activity")
      expect(out).to include("_No activity in this window._")
      expect(out).to include("## New knowledge")
      expect(out).to include("_No new facts in this window._")
      expect(out).to include("## Conflicts")
      expect(out).to include("_No open conflicts._")
      expect(out).to include("## Feedback")
      expect(out).to include("_No thumbs in this window._")
    end

    it "reports activity counts by event_type" do
      record_event(manager.project_store, "recall", {tool: "memory.recall", result_count: 3})
      record_event(manager.project_store, "recall", {tool: "memory.recall", result_count: 0})
      record_event(manager.project_store, "store_extraction", {facts_created: 2})

      command.call([])

      out = stdout.string
      expect(out).to include("**Moments recorded:** 3")
      expect(out).to include("- Recalls: 2")
      expect(out).to include("- Facts extracted: 1")
    end

    it "groups new facts by predicate" do
      create_fact(manager.project_store, predicate: "convention", object: "use tabs")
      create_fact(manager.project_store, predicate: "convention", object: "prefer do..end")
      create_fact(manager.project_store, predicate: "decision", object: "SQLite")

      command.call([])

      out = stdout.string
      expect(out).to include("**New active facts:** 3")
      expect(out).to include("- convention: 2")
      expect(out).to include("- decision: 1")
    end

    it "honors --since for the window" do
      # Create a fact with an ISO timestamp older than 7 days so the 7-day
      # default window would hide it but --since 30 would include it.
      long_ago = (Time.now.utc - 10 * 86_400).iso8601
      ent = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      fact_id = manager.project_store.insert_fact(
        subject_entity_id: ent, predicate: "convention", object_literal: "older",
        status: "active", scope: "project", confidence: 0.9
      )
      manager.project_store.facts.where(id: fact_id).update(created_at: long_ago)

      command.call(["--since", "7"])
      expect(stdout.string).to include("_No new facts in this window._")

      stdout.truncate(0)
      stdout.rewind
      command.call(["--since", "30"])
      expect(stdout.string).to include("**New active facts:** 1")
    end

    it "rejects a non-positive --since" do
      exit_code = command.call(["--since", "0"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/must be positive/)
    end

    it "writes to --output instead of stdout" do
      out_path = File.join(tmpdir, "digest.md")
      record_event(manager.project_store, "recall", {result_count: 1})

      command.call(["--output", out_path])

      expect(File.exist?(out_path)).to be true
      expect(File.read(out_path)).to include("## Activity")
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("Wrote digest to")
    end

    it "renders the empty Context cost section when there are no injections" do
      command.call([])
      expect(stdout.string).to include("## Context cost")
      expect(stdout.string).to include("_No context injections in the last 30 days._")
    end

    it "renders the empty Quality section when there are no facts yet" do
      command.call([])
      out = stdout.string
      expect(out).to include("## Quality")
      expect(out).to include("_No active facts to score yet._")
      expect(out).to include("**Rejection rate (in window):** 0 of 0")
    end

    it "reports live quality score and rejection rate when facts exist" do
      ent = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      manager.project_store.insert_fact(
        subject_entity_id: ent, predicate: "convention",
        object_literal: "Use frozen_string_literal because mutations cause subtle bugs",
        status: "active", scope: "project"
      )
      manager.project_store.insert_fact(
        subject_entity_id: ent, predicate: "convention",
        object_literal: "Bare convention without reason",
        status: "active", scope: "project"
      )
      manager.project_store.insert_fact(
        subject_entity_id: ent, predicate: "decision",
        object_literal: "Rejected idea, no reason",
        status: "rejected", scope: "project"
      )

      command.call([])

      out = stdout.string
      expect(out).to include("## Quality")
      expect(out).to include("**Live score (last 30d):**")
      expect(out).to include("Bare conclusions (decision/convention without reason): 1")
      expect(out).to include("**Rejection rate (in window):** 1 of 3 extracted facts rejected")
    end

    it "shows a historical block when older facts exist outside the live window" do
      ent = manager.project_store.find_or_create_entity(type: "repo", name: "app")
      old_id = manager.project_store.insert_fact(
        subject_entity_id: ent, predicate: "convention",
        object_literal: "Old bare convention",
        status: "active", scope: "project"
      )
      old_ts = (Time.now.utc - 60 * 86_400).iso8601
      manager.project_store.facts.where(id: old_id).update(created_at: old_ts)
      manager.project_store.insert_fact(
        subject_entity_id: ent, predicate: "convention",
        object_literal: "Fresh convention because reasons matter",
        status: "active", scope: "project"
      )

      command.call([])

      out = stdout.string
      expect(out).to include("**Live score (last 30d):**")
      expect(out).to include("_Historical (all active):")
      expect(out).to include("2 facts, 1 bare")
    end

    it "reports p50/p95/avg in Context cost when hook_context events exist" do
      [200, 400, 600].each do |tokens|
        record_event(manager.project_store, "hook_context",
          {context_tokens: tokens, context_length: tokens * 4})
      end

      command.call([])

      out = stdout.string
      expect(out).to include("## Context cost")
      expect(out).to include("**Per-session injected tokens (last 30d, n=3):**")
      expect(out).to include("- p50: 400 tokens")
      expect(out).to include("- p95: 600 tokens")
      expect(out).to include("- avg: 400 tokens")
    end

    it "surfaces feedback counts when thumbs exist" do
      record_event(manager.project_store, "recall", {result_count: 1})
      event_id = manager.project_store.activity_events.first[:id]
      manager.project_store.upsert_moment_feedback(event_id: event_id, verdict: "up")

      command.call([])

      out = stdout.string
      expect(out).to include("**Moments rated:** 1")
      expect(out).to include("- 👍 Up: 1")
      expect(out).to include("- Positive ratio: 100%")
    end
  end
end
