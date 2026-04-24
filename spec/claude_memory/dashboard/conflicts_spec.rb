# frozen_string_literal: true

require "digest"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::Conflicts do
  let(:tmpdir) { Dir.mktmpdir("dashboard_conflicts_test_#{Process.pid}") }
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
  let(:conflicts) { described_class.new(manager) }

  before { manager.ensure_both! }
  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def seed_conflict(store, object_a:, object_b:, predicate: "uses_database", notes: "mismatch")
    entity_id = store.find_or_create_entity(type: "repo", name: "test-app")
    fact_a = store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate, object_literal: object_a,
      status: "active", confidence: 0.9, scope: "project"
    )
    fact_b = store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate, object_literal: object_b,
      status: "disputed", confidence: 0.7, scope: "project"
    )
    ci_a = store.upsert_content_item(
      source: "test", text_hash: Digest::SHA256.hexdigest("a#{object_a}"), byte_len: 1,
      session_id: "sess-a", raw_text: "claims #{object_a}"
    )
    ci_b = store.upsert_content_item(
      source: "test", text_hash: Digest::SHA256.hexdigest("b#{object_b}"), byte_len: 1,
      session_id: "sess-b", raw_text: "claims #{object_b}"
    )
    store.insert_provenance(fact_id: fact_a, content_item_id: ci_a, quote: "uses #{object_a}", strength: "stated")
    store.insert_provenance(fact_id: fact_b, content_item_id: ci_b, quote: "uses #{object_b}", strength: "stated")
    conflict_id = store.insert_conflict(fact_a_id: fact_a, fact_b_id: fact_b, notes: notes)
    {conflict_id: conflict_id, fact_a: fact_a, fact_b: fact_b}
  end

  describe "#list" do
    it "returns zero when there are no conflicts" do
      result = conflicts.list

      expect(result[:total]).to eq(0)
      expect(result[:conflicts]).to eq([])
      expect(result[:counts]).to eq(
        project: {open: 0, resolved: 0, total: 0},
        global: {open: 0, resolved: 0, total: 0}
      )
    end

    it "lists project conflicts with fact previews" do
      seed_conflict(manager.project_store, object_a: "PostgreSQL", object_b: "MySQL")

      result = conflicts.list

      expect(result[:total]).to eq(1)
      expect(result[:scope]).to eq("project")
      expect(result[:status]).to eq("open")
      row = result[:conflicts].first
      expect(row[:status]).to eq("open")
      expect(row[:source]).to eq("project")
      expect(row[:fact_a_preview][:object]).to eq("PostgreSQL")
      expect(row[:fact_b_preview][:object]).to eq("MySQL")
    end

    it "applies limit and offset on a flat list" do
      3.times { |i| seed_conflict(manager.project_store, object_a: "A#{i}", object_b: "B#{i}") }

      result = conflicts.list("limit" => 2, "offset" => 1)

      expect(result[:total]).to eq(3)
      expect(result[:limit]).to eq(2)
      expect(result[:offset]).to eq(1)
      expect(result[:conflicts].size).to eq(2)
    end

    it "collapses duplicate conflicts and reports a group_size" do
      3.times { seed_conflict(manager.project_store, object_a: "PostgreSQL", object_b: "MySQL") }
      seed_conflict(manager.project_store, object_a: "Redis", object_b: "Memcached")

      result = conflicts.list

      expect(result[:total]).to eq(2)
      row = result[:conflicts].find { |r| r[:fact_a_preview][:object] == "PostgreSQL" }
      expect(row[:group_size]).to eq(3)
      expect(row[:group_member_ids].size).to eq(3)
    end

    it "treats order-swapped object pairs as the same group" do
      seed_conflict(manager.project_store, object_a: "A", object_b: "B")
      seed_conflict(manager.project_store, object_a: "b", object_b: "a ")

      result = conflicts.list

      expect(result[:total]).to eq(1)
      expect(result[:conflicts].first[:group_size]).to eq(2)
    end

    it "exposes raw counts alongside deduped counts" do
      3.times { seed_conflict(manager.project_store, object_a: "PostgreSQL", object_b: "MySQL") }

      result = conflicts.list

      expect(result[:counts][:project][:open]).to eq(1)
      expect(result[:raw_counts][:project][:open]).to eq(3)
    end

    it "reports counts across both scopes regardless of filter" do
      seed_conflict(manager.project_store, object_a: "A", object_b: "B")
      seed_conflict(manager.global_store, object_a: "G1", object_b: "G2")

      result = conflicts.list("scope" => "project")

      expect(result[:counts][:project][:total]).to eq(1)
      expect(result[:counts][:global][:total]).to eq(1)
    end

    it "answers distinct_open_counts for the sidebar" do
      3.times { seed_conflict(manager.project_store, object_a: "PostgreSQL", object_b: "MySQL") }
      seed_conflict(manager.global_store, object_a: "G1", object_b: "G2")

      counts = conflicts.distinct_open_counts

      expect(counts[:project]).to eq(1)
      expect(counts[:global]).to eq(1)
      expect(counts[:total]).to eq(2)
    end

    it "filters by status=all when requested" do
      seed_conflict(manager.project_store, object_a: "A", object_b: "B")

      result = conflicts.list("status" => "all")

      expect(result[:total]).to eq(1)
    end

    it "lists conflicts from both stores when scope=all" do
      seed_conflict(manager.project_store, object_a: "A", object_b: "B")
      seed_conflict(manager.global_store, object_a: "G1", object_b: "G2")

      result = conflicts.list("scope" => "all")

      sources = result[:conflicts].map { |r| r[:source] }.sort
      expect(sources).to eq(%w[global project])
    end
  end

  describe "#detail" do
    it "returns both sides with provenance" do
      seed = seed_conflict(manager.project_store, object_a: "PostgreSQL", object_b: "MySQL")

      result = conflicts.detail(seed[:conflict_id], "project")

      expect(result[:conflict][:id]).to eq(seed[:conflict_id])
      expect(result[:conflict][:source]).to eq("project")
      expect(result[:fact_a][:object]).to eq("PostgreSQL")
      expect(result[:fact_b][:object]).to eq("MySQL")
      expect(result[:fact_a][:provenance].first[:quote]).to eq("uses PostgreSQL")
    end

    it "rejects unknown scopes" do
      result = conflicts.detail(1, "mars")

      expect(result[:error]).to match(/Invalid scope/)
    end

    it "returns an error when the conflict id does not exist" do
      result = conflicts.detail(99_999, "project")

      expect(result[:error]).to match(/not found/)
    end
  end

  describe "#reject" do
    it "rejects the 'a' side and marks the conflict resolved" do
      seed = seed_conflict(manager.project_store, object_a: "A", object_b: "B")

      result = conflicts.reject(seed[:conflict_id], side: "a", reason: "wrong")

      expect(result[:success]).to be true
      expect(result[:rejected_fact_id]).to eq(seed[:fact_a])
      expect(result[:conflicts_resolved]).to be >= 1

      fact_a_row = manager.project_store.facts.where(id: seed[:fact_a]).first
      expect(fact_a_row[:status]).to eq("rejected")
    end

    it "rejects the 'b' side" do
      seed = seed_conflict(manager.project_store, object_a: "A", object_b: "B")

      result = conflicts.reject(seed[:conflict_id], side: "b")

      expect(result[:rejected_fact_id]).to eq(seed[:fact_b])
    end

    it "rejects an invalid side" do
      seed = seed_conflict(manager.project_store, object_a: "A", object_b: "B")

      result = conflicts.reject(seed[:conflict_id], side: "c")

      expect(result[:error]).to match(/Invalid side/)
    end
  end

  describe "#reject_similar" do
    it "rejects every opposing fact in open conflicts against the keeper" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "test-app")
      keeper = store.insert_fact(
        subject_entity_id: entity_id, predicate: "uses_database", object_literal: "sqlite",
        status: "active", confidence: 0.95, scope: "project"
      )
      losers = %w[postgresql mysql redis].map do |obj|
        store.insert_fact(
          subject_entity_id: entity_id, predicate: "uses_database", object_literal: obj,
          status: "disputed", confidence: 0.6, scope: "project"
        )
      end
      losers.each { |loser| store.insert_conflict(fact_a_id: keeper, fact_b_id: loser) }

      result = conflicts.reject_similar(keeper)

      expect(result[:rejected_fact_ids]).to match_array(losers)
      expect(result[:keeper_fact_id]).to eq(keeper)
      losers.each do |loser|
        expect(store.facts.where(id: loser).get(:status)).to eq("rejected")
      end
      expect(store.facts.where(id: keeper).get(:status)).to eq("active")
    end

    it "returns zero when no conflicts reference the keeper" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "test-app")
      keeper = store.insert_fact(
        subject_entity_id: entity_id, predicate: "uses_database", object_literal: "sqlite",
        status: "active", confidence: 0.9, scope: "project"
      )

      result = conflicts.reject_similar(keeper)

      expect(result[:rejected_fact_ids]).to eq([])
      expect(result[:conflicts_resolved]).to eq(0)
    end

    it "does not double-reject a loser that appears in multiple conflicts" do
      store = manager.project_store
      entity_id = store.find_or_create_entity(type: "repo", name: "test-app")
      keeper = store.insert_fact(
        subject_entity_id: entity_id, predicate: "uses_database", object_literal: "sqlite",
        status: "active", confidence: 0.9, scope: "project"
      )
      loser = store.insert_fact(
        subject_entity_id: entity_id, predicate: "uses_database", object_literal: "postgresql",
        status: "disputed", confidence: 0.5, scope: "project"
      )
      store.insert_conflict(fact_a_id: keeper, fact_b_id: loser)
      store.insert_conflict(fact_a_id: loser, fact_b_id: keeper)

      result = conflicts.reject_similar(keeper)

      expect(result[:rejected_fact_ids]).to eq([loser])
    end
  end
end
