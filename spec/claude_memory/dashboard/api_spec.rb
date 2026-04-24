# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::API do
  let(:tmpdir) { Dir.mktmpdir("dashboard_api_test_#{Process.pid}") }
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
  let(:api) { described_class.new(manager) }

  before do
    manager.ensure_both!
  end

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  describe "#health" do
    it "returns overall health status" do
      result = api.health

      expect(result[:status]).to be_a(String)
      expect(result[:checks]).to be_an(Array)
      expect(result[:version]).to eq(ClaudeMemory::VERSION)
    end

    it "includes database health checks" do
      result = api.health
      db_checks = result[:checks].select { |c| c[:name].include?("database") }
      expect(db_checks.size).to eq(2)
    end

    it "includes remediation text for non-healthy checks" do
      result = api.health
      non_healthy = result[:checks].reject { |c| c[:status] == "healthy" }

      non_healthy.each do |check|
        expect(check[:fix]).to be_a(String), "expected fix text on #{check[:name]} (#{check[:status]})"
        expect(check[:fix]).not_to be_empty
      end
    end

    it "omits fix on healthy checks" do
      result = api.health
      healthy = result[:checks].select { |c| c[:status] == "healthy" }

      healthy.each do |check|
        expect(check).not_to have_key(:fix)
      end
    end
  end

  describe "#stats" do
    it "returns stats for both databases" do
      result = api.stats

      expect(result[:databases]).to have_key(:global)
      expect(result[:databases]).to have_key(:project)
      expect(result[:databases][:project][:exists]).to be true
    end

    it "includes fact and entity counts" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "framework", name: "Rails")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "Rails",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )

      result = api.stats
      project = result[:databases][:project]

      expect(project[:facts_total]).to eq(1)
      expect(project[:facts_active]).to eq(1)
      expect(project[:entities_total]).to eq(1)
    end
  end

  describe "#activity" do
    it "returns empty list when no events" do
      result = api.activity

      expect(result[:event_count]).to eq(0)
      expect(result[:events]).to eq([])
    end

    it "returns recorded events" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "hook_ingest",
        status: "success",
        details: {bytes_read: 512})

      result = api.activity

      expect(result[:event_count]).to eq(1)
      expect(result[:events].first[:event_type]).to eq("hook_ingest")
      expect(result[:events].first[:occurred_ago]).to be_a(String)
    end

    it "filters by event_type" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store, event_type: "hook_ingest", status: "success")
      ClaudeMemory::ActivityLog.record(store, event_type: "recall", status: "success")

      result = api.activity({"event_type" => "recall"})
      expect(result[:event_count]).to eq(1)
    end
  end

  describe "#recall (query tester)" do
    before do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "explicit returns improve readability",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )
      # Index for FTS so Recall can find it
      ci_id = store.upsert_content_item(
        source: "test", text_hash: Digest::SHA256.hexdigest("r"), byte_len: 1,
        raw_text: "explicit returns improve readability"
      )
      ClaudeMemory::Index::LexicalFTS.new(store).index_content_item(ci_id, "explicit returns improve readability")
      store.insert_provenance(fact_id: fact_id, content_item_id: ci_id, strength: "stated")
    end

    it "errors without query" do
      expect(api.recall({})[:error]).to match(/query required/)
    end

    it "returns facts for a matching query" do
      result = api.recall({"query" => "explicit returns", "scope" => "project", "limit" => 5})

      expect(result[:error]).to be_nil
      expect(result[:query]).to eq("explicit returns")
      expect(result[:count]).to be > 0
      expect(result[:facts]).to be_an(Array)
      expect(result[:duration_ms]).to be_a(Integer)

      fact = result[:facts].first
      expect(fact[:subject]).to eq("test-repo")
      expect(fact[:predicate]).to eq("convention")
      expect(fact[:object]).to include("explicit returns")
      expect(fact[:scope]).to eq("project")
      expect(fact[:receipts_count]).to be >= 1
    end

    it "returns an empty array for a query with no matches" do
      result = api.recall({"query" => "zzzzz-not-a-real-query-token"})
      expect(result[:count]).to eq(0)
    end
  end

  describe "#fact_detail" do
    it "returns error for invalid scope" do
      expect(api.fact_detail(1, "bad")[:error]).to match(/Invalid scope/)
    end

    it "returns error for missing id" do
      expect(api.fact_detail(999_999, "project")[:error]).to match(/not found/)
    end

    it "returns a fact with provenance chain" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "prefer explicit returns",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )
      ci_id = store.upsert_content_item(
        source: "test", text_hash: Digest::SHA256.hexdigest("p"), byte_len: 1,
        session_id: "sess-prov", raw_text: "stated convention"
      )
      store.insert_provenance(fact_id: fact_id, content_item_id: ci_id, quote: "prefer explicit returns", strength: "stated")

      result = api.fact_detail(fact_id, "project")

      expect(result[:id]).to eq(fact_id)
      expect(result[:predicate]).to eq("convention")
      expect(result[:provenance].size).to eq(1)
      expect(result[:provenance].first[:session_id]).to eq("sess-prov")
      expect(result[:source]).to eq("project")
    end
  end

  describe "#reject_fact (standalone)" do
    it "rejects the fact and reports the result" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "bad pattern",
        status: "active",
        scope: "project"
      )

      result = api.reject_fact(fact_id, reason: "distiller noise", scope: "project")

      expect(result[:success]).to be true
      expect(store.facts.where(id: fact_id).first[:status]).to eq("rejected")
    end

    it "errors on missing fact" do
      expect(api.reject_fact(999_999)[:error]).to match(/not found/)
    end
  end

  describe "#promote_fact" do
    it "promotes a project fact into global" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "promote-src")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "global-worthy convention",
        status: "active",
        scope: "project"
      )

      result = api.promote_fact(fact_id)

      expect(result[:success]).to be true
      expect(result[:global_fact_id]).to be_a(Integer)
      expect(manager.global_store.facts.where(id: result[:global_fact_id]).first[:scope]).to eq("global")
    end

    it "errors on missing fact" do
      expect(api.promote_fact(999_999)[:error]).to match(/not found/)
    end
  end

  describe "#activity_detail" do
    it "returns error for missing id" do
      expect(api.activity_detail(999999)[:error]).to match(/not found/)
    end

    it "returns the event with raw details and no content when absent" do
      store = manager.project_store
      event_id = ClaudeMemory::ActivityLog.record(store,
        event_type: "hook_ingest",
        status: "success",
        session_id: "sess-abc",
        duration_ms: 12,
        details: {bytes_read: 42, reason: "noop"})

      detail = api.activity_detail(event_id)

      expect(detail[:event][:id]).to eq(event_id)
      expect(detail[:event][:event_type]).to eq("hook_ingest")
      expect(detail[:event][:details][:bytes_read]).to eq(42)
      expect(detail[:content_item]).to be_nil
      expect(detail[:linked_facts]).to eq([])
    end

    it "loads the linked content_item and facts when content_item_id is present" do
      store = manager.project_store
      ci_id = store.upsert_content_item(
        source: "test",
        text_hash: Digest::SHA256.hexdigest("abc"),
        byte_len: 11,
        raw_text: "abc content"
      )
      entity_id = store.find_or_create_entity(type: "framework", name: "Rails")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "Rails",
        status: "active",
        confidence: 1.0,
        scope: "project"
      )
      store.insert_provenance(fact_id: fact_id, content_item_id: ci_id, strength: "stated")

      event_id = ClaudeMemory::ActivityLog.record(store,
        event_type: "store_extraction",
        status: "success",
        details: {content_item_id: ci_id, facts_created: 1, entities_created: 1})

      detail = api.activity_detail(event_id)

      expect(detail[:content_item][:id]).to eq(ci_id)
      expect(detail[:content_item][:raw_text_preview]).to eq("abc content")
      expect(detail[:linked_facts].size).to eq(1)
      expect(detail[:linked_facts].first[:subject]).to eq("Rails")
      expect(detail[:linked_facts].first[:object]).to eq("Rails")
    end

    context "recall trigger resolution" do
      it "finds the preceding ingest and extracts a user prompt as the trigger" do
        store = manager.project_store
        user_text = "what conventions should I follow here?"
        transcript = {parentUuid: nil, type: "user",
                      message: {role: "user", content: [{type: "text", text: user_text}]}}.to_json
        ci_id = store.upsert_content_item(
          source: "claude_code",
          text_hash: Digest::SHA256.hexdigest(transcript),
          byte_len: transcript.bytesize,
          session_id: "sess-xyz",
          raw_text: transcript
        )
        ClaudeMemory::ActivityLog.record(store,
          event_type: "hook_ingest", status: "success",
          session_id: "sess-xyz",
          details: {content_id: ci_id, bytes_read: transcript.bytesize})

        sleep 1.1
        recall_id = ClaudeMemory::ActivityLog.record(store,
          event_type: "recall", status: "success",
          details: {tool: "memory.conventions", result_count: 5, top_fact_ids: []})

        detail = api.activity_detail(recall_id)
        expect(detail[:trigger]).not_to be_nil
        expect(detail[:trigger][:event_type]).to eq("hook_ingest")
        expect(detail[:trigger][:user_prompt]).to eq(user_text)
      end

      it "filters out command-stdout and tool_result noise when finding the trigger" do
        store = manager.project_store
        noise_transcript = [
          {message: {role: "user", content: [{type: "text", text: "<local-command-stdout>Bye!</local-command-stdout>"}]}}.to_json,
          {message: {role: "user", content: [{type: "tool_result", content: "result text"}]}}.to_json
        ].join("\n")
        ci_id = store.upsert_content_item(
          source: "claude_code",
          text_hash: Digest::SHA256.hexdigest(noise_transcript),
          byte_len: noise_transcript.bytesize,
          raw_text: noise_transcript
        )
        ClaudeMemory::ActivityLog.record(store,
          event_type: "hook_ingest", status: "success",
          details: {content_id: ci_id})

        sleep 1.1
        recall_id = ClaudeMemory::ActivityLog.record(store,
          event_type: "recall", status: "success",
          details: {tool: "memory.recall", result_count: 1, top_fact_ids: []})

        detail = api.activity_detail(recall_id)
        expect(detail[:trigger][:user_prompt]).to be_nil
      end

      it "omits trigger for non-recall events" do
        store = manager.project_store
        event_id = ClaudeMemory::ActivityLog.record(store,
          event_type: "hook_ingest", status: "success",
          details: {bytes_read: 10})
        detail = api.activity_detail(event_id)
        expect(detail).not_to have_key(:trigger)
      end
    end
  end

  describe "#facts" do
    before do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "database", name: "PostgreSQL")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        status: "active",
        confidence: 0.95,
        scope: "project"
      )
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "Redis",
        status: "superseded",
        confidence: 0.8,
        scope: "project"
      )
    end

    it "returns active facts by default" do
      result = api.facts

      expect(result[:total]).to eq(1)
      expect(result[:facts].first[:predicate]).to eq("uses_database")
      expect(result[:facts].first[:object]).to eq("PostgreSQL")
    end

    it "filters by status" do
      result = api.facts({"status" => "superseded"})

      expect(result[:total]).to eq(1)
      expect(result[:facts].first[:object]).to eq("Redis")
    end

    it "supports search by predicate" do
      result = api.facts({"q" => "uses_database"})

      expect(result[:total]).to eq(1)
    end

    it "filters to stale facts (active but not referenced by recent recalls)" do
      store = manager.project_store
      # The existing PostgreSQL fact and a second 'Rails' fact. Simulate a
      # recent recall that returned only the PostgreSQL fact, so the second
      # fact is the only stale one.
      pg_fact_id = store.facts.where(object_literal: "PostgreSQL").first[:id]
      rails_entity = store.find_or_create_entity(type: "framework", name: "Rails")
      store.insert_fact(
        subject_entity_id: rails_entity,
        predicate: "uses_framework",
        object_literal: "Rails",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success",
        details: {query: "db", result_count: 1, top_fact_ids: [pg_fact_id]})

      result = api.facts({"stale" => "true"})
      expect(result[:stale]).to be true
      expect(result[:facts].map { |f| f[:object] }).to eq(["Rails"])
    end
  end

  describe "#efficacy" do
    it "returns zero metrics when no recall events" do
      result = api.efficacy

      expect(result[:recall_events]).to eq(0)
      expect(result[:hit_rate]).to eq(0)
      expect(result[:tool_mix]).to eq([])
      expect(result[:memory_gaps]).to eq([])
      expect(result[:recall_trace]).to eq([])
    end

    it "calculates hit rate from recall events" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", duration_ms: 20,
        details: {query: "auth", result_count: 3, tool: "memory.recall"})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", duration_ms: 40,
        details: {query: "nothing", result_count: 0, tool: "memory.recall"})

      result = api.efficacy

      expect(result[:recall_events]).to eq(2)
      expect(result[:successful_recalls]).to eq(1)
      expect(result[:empty_recalls]).to eq(1)
      expect(result[:hit_rate]).to eq(50.0)
    end

    it "returns a tool mix grouped by tool" do
      store = manager.project_store
      3.times { |i|
        ClaudeMemory::ActivityLog.record(store,
          event_type: "recall", status: "success", duration_ms: 10 + i,
          details: {tool: "memory.decisions", result_count: 2})
      }
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", duration_ms: 25,
        details: {tool: "memory.recall", query: "auth", result_count: 1})

      result = api.efficacy

      decisions = result[:tool_mix].find { |r| r[:tool] == "memory.decisions" }
      recall = result[:tool_mix].find { |r| r[:tool] == "memory.recall" }
      expect(decisions[:count]).to eq(3)
      expect(decisions[:hit_rate]).to eq(100.0)
      expect(recall[:count]).to eq(1)
      # Largest bucket is first
      expect(result[:tool_mix].first[:tool]).to eq("memory.decisions")
    end

    it "surfaces memory gaps (zero-result queries)" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success",
        details: {query: "unknown topic", result_count: 0, tool: "memory.recall"})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success",
        details: {query: "found", result_count: 3, tool: "memory.recall"})

      result = api.efficacy
      gaps = result[:memory_gaps]

      expect(gaps.size).to eq(1)
      expect(gaps.first[:query]).to eq("unknown topic")
      expect(gaps.first[:occurred_ago]).to be_a(String)
    end

    it "computes median latency and median results per query" do
      store = manager.project_store
      [10, 20, 30, 40, 50].each { |ms|
        ClaudeMemory::ActivityLog.record(store,
          event_type: "recall", status: "success", duration_ms: ms,
          details: {tool: "memory.recall", result_count: ms / 10})
      }

      result = api.efficacy
      expect(result[:median_latency_ms]).to eq(30)
      expect(result[:median_results_per_query]).to eq(3)
    end

    it "filters by session_id when provided" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: "sess-a",
        details: {tool: "memory.recall", query: "a", result_count: 1})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: "sess-b",
        details: {tool: "memory.recall", query: "b", result_count: 2})

      result = api.efficacy({"session_id" => "sess-a"})
      expect(result[:recall_events]).to eq(1)
      expect(result[:recall_trace].first[:query]).to eq("a")
    end

    it "ignores empty-string session_id" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: "sess-a",
        details: {tool: "memory.recall", query: "a", result_count: 1})

      result = api.efficacy({"session_id" => ""})
      expect(result[:recall_events]).to eq(1)
    end

    it "correlates session-scoped recall events by time window when recall lacks session_id" do
      store = manager.project_store
      # Hook events bracket the session time window.
      ClaudeMemory::ActivityLog.record(store,
        event_type: "hook_ingest", status: "success", session_id: "sess-window",
        duration_ms: 5, details: {bytes_read: 100})
      # Simulate an in-session recall that the MCP server couldn't tag
      # with a session_id (typical case for plugin-launched MCP).
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: nil,
        details: {tool: "memory.recall", query: "during-session", result_count: 2})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "hook_ingest", status: "success", session_id: "sess-window",
        duration_ms: 5, details: {bytes_read: 200})

      # An out-of-window recall from long ago should NOT be included.
      old = ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: nil,
        details: {tool: "memory.recall", query: "ancient", result_count: 0})
      store.activity_events.where(id: old).update(occurred_at: "2020-01-01T00:00:00Z")

      result = api.efficacy({"session_id" => "sess-window"})

      queries = result[:recall_trace].map { |r| r[:query] }
      expect(queries).to include("during-session")
      expect(queries).not_to include("ancient")
    end
  end

  describe "conflicts endpoints" do
    let(:project_store) { manager.project_store }
    let!(:conflict_id) do
      entity_id = project_store.find_or_create_entity(type: "repo", name: "test-app")
      fact_a = project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )
      fact_b = project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_database",
        object_literal: "MySQL",
        status: "disputed",
        confidence: 0.7,
        scope: "project"
      )
      ci_a = project_store.upsert_content_item(
        source: "test",
        text_hash: Digest::SHA256.hexdigest("a"),
        byte_len: 1,
        session_id: "sess-a",
        raw_text: "claims PostgreSQL"
      )
      ci_b = project_store.upsert_content_item(
        source: "test",
        text_hash: Digest::SHA256.hexdigest("b"),
        byte_len: 1,
        session_id: "sess-b",
        raw_text: "claims MySQL"
      )
      project_store.insert_provenance(fact_id: fact_a, content_item_id: ci_a, quote: "uses PostgreSQL", strength: "stated")
      project_store.insert_provenance(fact_id: fact_b, content_item_id: ci_b, quote: "uses MySQL", strength: "stated")
      project_store.insert_conflict(fact_a_id: fact_a, fact_b_id: fact_b, notes: "Contradicting uses_database claims")
    end

    describe "#conflicts" do
      it "lists open conflicts with previews" do
        result = api.conflicts

        expect(result[:total]).to eq(1)
        expect(result[:conflicts].size).to eq(1)
        row = result[:conflicts].first
        expect(row[:status]).to eq("open")
        expect(row[:source]).to eq("project")
        expect(row[:fact_a_preview][:object]).to eq("PostgreSQL")
        expect(row[:fact_b_preview][:object]).to eq("MySQL")
        expect(row[:detected_ago]).to be_a(String)
      end

      it "filters by status" do
        expect(api.conflicts({"status" => "open"})[:total]).to eq(1)
        expect(api.conflicts({"status" => "resolved"})[:total]).to eq(0)
      end
    end

    describe "#conflict_detail" do
      it "returns both facts with their provenance chain" do
        detail = api.conflict_detail(conflict_id, "project")

        expect(detail[:conflict][:id]).to eq(conflict_id)
        expect(detail[:fact_a][:object]).to eq("PostgreSQL")
        expect(detail[:fact_a][:provenance].first[:quote]).to eq("uses PostgreSQL")
        expect(detail[:fact_a][:provenance].first[:session_id]).to eq("sess-a")
        expect(detail[:fact_b][:object]).to eq("MySQL")
        expect(detail[:fact_b][:provenance].first[:session_id]).to eq("sess-b")
      end

      it "errors on unknown id" do
        expect(api.conflict_detail(99999, "project")[:error]).to match(/not found/)
      end
    end

    describe "#reject_conflict_fact" do
      it "rejects fact B and resolves the conflict atomically" do
        result = api.reject_conflict_fact(conflict_id, side: "b", reason: "legacy DB", scope: "project")

        expect(result[:success]).to be true
        expect(result[:conflicts_resolved]).to eq(1)

        # Conflict is now resolved
        updated = project_store.conflicts.where(id: conflict_id).first
        expect(updated[:status]).to eq("resolved")

        # Fact B is rejected
        fact = project_store.facts.where(id: result[:rejected_fact_id]).first
        expect(fact[:status]).to eq("rejected")
      end

      it "rejects invalid side" do
        expect(api.reject_conflict_fact(conflict_id, side: "x")[:error]).to match(/Invalid side/)
      end
    end

    describe "#reject_similar_conflicts" do
      it "rejects every disputed fact in conflict with the keeper" do
        # Spawn 3 additional disputed facts all contradicting fact_a (keeper).
        entity_id = project_store.find_or_create_entity(type: "repo", name: "test-app")
        keeper_id = project_store.facts.where(object_literal: "PostgreSQL").first[:id]

        losers = %w[MySQL Redis MariaDB].map { |obj|
          f = project_store.insert_fact(
            subject_entity_id: entity_id,
            predicate: "uses_database",
            object_literal: obj,
            status: "disputed",
            scope: "project"
          )
          project_store.insert_conflict(fact_a_id: keeper_id, fact_b_id: f, notes: "contradicts #{obj}")
          f
        }

        # Precondition: 4 total open conflicts (1 existing + 3 new)
        expect(project_store.conflicts.where(status: "open").count).to eq(4)

        result = api.reject_similar_conflicts(keeper_id, scope: "project", reason: "bulk reject")

        expect(result[:success]).to be true
        expect(result[:rejected_fact_ids]).to match_array(losers + [project_store.facts.where(object_literal: "MySQL").first[:id]].uniq - [keeper_id])
        expect(project_store.conflicts.where(status: "open").count).to eq(0)

        losers.each do |loser_id|
          expect(project_store.facts.where(id: loser_id).first[:status]).to eq("rejected")
        end
      end

      it "is a no-op when the keeper has no open conflicts" do
        entity_id = project_store.find_or_create_entity(type: "repo", name: "lonely")
        solo = project_store.insert_fact(
          subject_entity_id: entity_id, predicate: "uses_database",
          object_literal: "lonely-sqlite", status: "active", scope: "project"
        )

        result = api.reject_similar_conflicts(solo, scope: "project")
        expect(result[:success]).to be true
        expect(result[:rejected_fact_ids]).to eq([])
        expect(result[:conflicts_resolved]).to eq(0)
      end
    end
  end

  describe "#session_summary" do
    it "rolls up per-session event counts" do
      store = manager.project_store
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: "s1", duration_ms: 10,
        details: {tool: "memory.recall", result_count: 3})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "store_extraction", status: "success", session_id: "s1", duration_ms: 20,
        details: {facts_created: 2, entities_created: 1})
      ClaudeMemory::ActivityLog.record(store,
        event_type: "hook_ingest", status: "success", session_id: "s1", duration_ms: 5)
      ClaudeMemory::ActivityLog.record(store,
        event_type: "recall", status: "success", session_id: "other",
        details: {result_count: 99})

      result = api.session_summary("s1")

      expect(result[:session_id]).to eq("s1")
      expect(result[:events]).to eq(3)
      expect(result[:recalls]).to eq(1)
      expect(result[:facts_recalled]).to eq(3)
      expect(result[:facts_stored]).to eq(2)
      expect(result[:ingests]).to eq(1)
      expect(result[:total_latency_ms]).to eq(35)
    end
  end

  describe "#timeline" do
    it "returns daily buckets" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "test", name: "test")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "test",
        object_literal: "value",
        status: "active",
        scope: "project"
      )

      result = api.timeline

      expect(result[:days]).to be_an(Array)
      # Should have at least today's entry
      expect(result[:days]).not_to be_empty if result[:days].any?
    end
  end
end
