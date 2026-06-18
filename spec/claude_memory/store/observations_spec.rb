# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Store::SQLiteStore, "observations" do
  let(:db_path) { File.join(Dir.tmpdir, "claude_memory_obs_test_#{Process.pid}.sqlite3") }
  let(:store) { described_class.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  it "creates the observations table during migration" do
    expect(store.db.table_exists?(:observations)).to be true
  end

  describe "#insert_observation" do
    it "inserts a row and returns its id" do
      id = store.insert_observation(body: "decided to use SQLite", kind: "decision", priority: 1)
      expect(id).to be_a(Integer)
      row = store.observations.where(id: id).first
      expect(row[:body]).to eq("decided to use SQLite")
      expect(row[:kind]).to eq("decision")
      expect(row[:status]).to eq("active")
    end

    it "estimates token_count from the body when not given" do
      id = store.insert_observation(body: "a" * 40)
      expect(store.observations.where(id: id).get(:token_count)).to eq(10)
    end

    it "preserves an explicit token_count" do
      id = store.insert_observation(body: "x", token_count: 99)
      expect(store.observations.where(id: id).get(:token_count)).to eq(99)
    end
  end

  describe "#recent_observations" do
    before do
      store.insert_observation(body: "old info", priority: 3, scope: "project", observed_at: "2026-01-01T00:00:00Z")
      store.insert_observation(body: "new important", priority: 1, scope: "project", observed_at: "2026-06-01T00:00:00Z")
      store.insert_observation(body: "global note", priority: 2, scope: "global", observed_at: "2026-03-01T00:00:00Z")
    end

    it "returns active rows newest-first" do
      rows = store.recent_observations(scope: "project")
      expect(rows.map { |r| r[:body] }).to eq(["new important", "old info"])
    end

    it "filters by scope" do
      expect(store.recent_observations(scope: "global").map { |r| r[:body] }).to eq(["global note"])
    end

    it "filters by min_priority (important-only)" do
      rows = store.recent_observations(min_priority: ClaudeMemory::Domain::Observation::IMPORTANT)
      expect(rows.map { |r| r[:body] }).to eq(["new important"])
    end

    it "respects the limit" do
      expect(store.recent_observations(limit: 1).size).to eq(1)
    end
  end

  describe "#tombstone_observation" do
    it "marks the row consolidated and links it, preserving the row (append-only)" do
      old_id = store.insert_observation(body: "superseded")
      new_id = store.insert_observation(body: "consolidated summary")

      expect(store.tombstone_observation(old_id, into_id: new_id)).to be true

      row = store.observations.where(id: old_id).first
      expect(row[:status]).to eq("consolidated")
      expect(row[:consolidated_into]).to eq(new_id)
      expect(row[:reflected_at]).not_to be_nil
      # row is preserved, not deleted
      expect(store.observations.where(id: old_id).count).to eq(1)
      # and excluded from active recall
      expect(store.recent_observations.map { |r| r[:id] }).to eq([new_id])
    end

    it "returns false when the id does not exist" do
      expect(store.tombstone_observation(9999, into_id: 1)).to be false
    end
  end

  describe "#expire_observation" do
    it "marks the row expired (no consolidation target), preserving it" do
      id = store.insert_observation(body: "stale info", priority: 3)

      expect(store.expire_observation(id)).to be true

      row = store.observations.where(id: id).first
      expect(row[:status]).to eq("expired")
      expect(row[:consolidated_into]).to be_nil
      expect(row[:reflected_at]).not_to be_nil
      expect(store.observations.where(id: id).count).to eq(1)
      expect(store.recent_observations).to be_empty
    end

    it "returns false when the id does not exist" do
      expect(store.expire_observation(9999)).to be false
    end
  end

  describe "promotion support" do
    it "#increment_corroboration adds to the sighting count" do
      id = store.insert_observation(body: "x")
      expect(store.observations.where(id: id).get(:corroboration_count)).to eq(1)
      store.increment_corroboration(id, by: 2)
      expect(store.observations.where(id: id).get(:corroboration_count)).to eq(3)
    end

    it "#mark_observation_promoted records the fact and timestamp, preserving the row" do
      id = store.insert_observation(body: "x")
      expect(store.mark_observation_promoted(id, fact_id: 42)).to be true
      row = store.observations.where(id: id).first
      expect(row[:promoted_fact_id]).to eq(42)
      expect(row[:promoted_at]).not_to be_nil
    end

    describe "#observations_for_fact" do
      it "returns observations promoted into the given fact (reverse of promoted_fact_id)" do
        a = store.insert_observation(body: "use SQLite", kind: "decision", priority: 1)
        b = store.insert_observation(body: "elsewhere", kind: "event", priority: 3)
        store.mark_observation_promoted(a, fact_id: 7)
        store.mark_observation_promoted(b, fact_id: 9)

        rows = store.observations_for_fact(7)
        expect(rows.map { |r| r[:id] }).to eq([a])
        expect(rows.first).to include(:body, :kind, :corroboration_count, :observed_at)
      end

      it "returns [] when no observations promoted into the fact" do
        expect(store.observations_for_fact(123)).to be_empty
      end
    end

    describe "#promotion_candidates" do
      it "returns only active, unpromoted observations at/above the corroboration threshold" do
        corroborated = store.insert_observation(body: "corroborated", priority: 1)
        store.increment_corroboration(corroborated, by: 1) # -> 2
        store.insert_observation(body: "one-off", priority: 1) # count 1, excluded
        promoted = store.insert_observation(body: "already promoted", priority: 1)
        store.increment_corroboration(promoted, by: 5)
        store.mark_observation_promoted(promoted, fact_id: 1)

        ids = store.promotion_candidates(min_corroboration: 2).map { |r| r[:id] }
        expect(ids).to eq([corroborated])
      end

      it "orders by corroboration_count descending" do
        a = store.insert_observation(body: "a")
        store.increment_corroboration(a, by: 1) # 2
        b = store.insert_observation(body: "b")
        store.increment_corroboration(b, by: 4) # 5

        expect(store.promotion_candidates(min_corroboration: 2).map { |r| r[:id] }).to eq([b, a])
      end
    end
  end
end
