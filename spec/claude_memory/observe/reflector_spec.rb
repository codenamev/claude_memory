# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Observe::Reflector do
  let(:db_path) { File.join(Dir.tmpdir, "reflector_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def days_ago(n)
    (Time.now - n * 86400).utc.iso8601
  end

  describe "#reflect! dedupe" do
    it "collapses near-identical observations into the newest, tombstoning losers" do
      old = store.insert_observation(body: "Decided to ship", priority: 1, observed_at: days_ago(10))
      new = store.insert_observation(body: "decided   to ship", priority: 1, observed_at: days_ago(1))

      result = described_class.new(store).reflect!

      expect(result.deduped).to eq(1)
      expect(store.recent_observations.map { |o| o[:id] }).to eq([new])
      loser = store.observations.where(id: old).first
      expect(loser[:status]).to eq("consolidated")
      expect(loser[:consolidated_into]).to eq(new)
    end

    it "folds the losers' corroboration counts into the keeper (promotion signal)" do
      store.insert_observation(body: "use SQLite", priority: 1, observed_at: days_ago(10))
      keep = store.insert_observation(body: "use   SQLite", priority: 1, observed_at: days_ago(1))

      described_class.new(store).reflect!

      expect(store.observations.where(id: keep).get(:corroboration_count)).to eq(2)
      expect(store.promotion_candidates(min_corroboration: 2).map { |r| r[:id] }).to eq([keep])
    end

    it "keeps observations with different bodies or different scopes apart" do
      store.insert_observation(body: "alpha", priority: 1, scope: "project")
      store.insert_observation(body: "beta", priority: 1, scope: "project")
      store.insert_observation(body: "alpha", priority: 1, scope: "global")

      expect(described_class.new(store).reflect!.deduped).to eq(0)
      expect(store.recent_observations(limit: 50).size).to eq(3)
    end
  end

  describe "#reflect! expire_stale_info" do
    it "expires info-level (priority 3) observations older than the TTL" do
      stale = store.insert_observation(body: "old chatter", priority: 3, observed_at: days_ago(60))

      expect(described_class.new(store, info_ttl_days: 30).reflect!.expired).to eq(1)
      expect(store.observations.where(id: stale).get(:status)).to eq("expired")
    end

    it "never expires important (🔴) or maybe (🟡), regardless of age" do
      imp = store.insert_observation(body: "old important", priority: 1, observed_at: days_ago(365))
      maybe = store.insert_observation(body: "old maybe", priority: 2, observed_at: days_ago(365))

      expect(described_class.new(store).reflect!.expired).to eq(0)
      expect(store.observations.where(id: imp).get(:status)).to eq("active")
      expect(store.observations.where(id: maybe).get(:status)).to eq("active")
    end

    it "keeps recent info observations" do
      store.insert_observation(body: "recent chatter", priority: 3, observed_at: days_ago(1))
      expect(described_class.new(store, info_ttl_days: 30).reflect!.expired).to eq(0)
    end
  end

  it "preserves every row (append-only — nothing is deleted)" do
    store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(5))
    store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(1))
    store.insert_observation(body: "stale", priority: 3, observed_at: days_ago(90))

    described_class.new(store).reflect!

    expect(store.observations.count).to eq(3)
  end

  it "is idempotent — a second pass changes nothing" do
    store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(5))
    store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(1))
    store.insert_observation(body: "stale", priority: 3, observed_at: days_ago(90))

    described_class.new(store).reflect!
    second = described_class.new(store).reflect!

    expect(second.deduped).to eq(0)
    expect(second.expired).to eq(0)
  end
end
