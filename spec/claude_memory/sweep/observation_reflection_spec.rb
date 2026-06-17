# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe "Sweep observation reflection" do
  let(:db_path) { File.join(Dir.tmpdir, "sweep_obs_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def days_ago(n)
    (Time.now - n * 86400).utc.iso8601
  end

  describe ClaudeMemory::Sweep::Maintenance, "#reflect_observations" do
    it "delegates to the Reflector and returns dedupe/expire counts" do
      store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(5))
      store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(1))
      store.insert_observation(body: "stale", priority: 3, observed_at: days_ago(90))

      result = described_class.new(store).reflect_observations

      expect(result).to eq(deduped: 1, expired: 1)
    end

    it "no-ops gracefully when the observations table is absent" do
      fake = instance_double(ClaudeMemory::Store::SQLiteStore)
      db = instance_double(Sequel::Database)
      allow(fake).to receive(:db).and_return(db)
      allow(db).to receive(:table_exists?).with(:observations).and_return(false)

      expect(described_class.new(fake).reflect_observations).to eq(deduped: 0, expired: 0)
    end
  end

  describe ClaudeMemory::Sweep::Sweeper, "observation reflection" do
    it "runs reflection during a normal sweep and reports the counts in stats" do
      store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(5))
      store.insert_observation(body: "dup", priority: 1, observed_at: days_ago(1))
      store.insert_observation(body: "stale", priority: 3, observed_at: days_ago(90))

      stats = described_class.new(store).run!(budget_seconds: 5)

      expect(stats[:observations_deduped]).to eq(1)
      expect(stats[:observations_expired]).to eq(1)
    end
  end
end
