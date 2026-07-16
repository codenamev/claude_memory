# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Observe::ObservationStats do
  let(:db_path) { File.join(Dir.tmpdir, "claude_memory_obs_stats_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  subject(:stats) { described_class.new([store]) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#total_count / #totals" do
    it "counts across statuses" do
      store.insert_observation(body: "active one", kind: "event", priority: 3)
      c = store.insert_observation(body: "will consolidate a", priority: 3)
      d = store.insert_observation(body: "will consolidate b", priority: 3)
      store.consolidate_observations([c, d], body: "merged")

      # active-one + c + d + the new merged row = 4 rows total
      expect(stats.total_count).to eq(4)
      totals = stats.totals
      expect(totals[:active]).to eq(2)   # active-one + the merged row
      expect(totals[:consolidated]).to eq(2) # c + d
      expect(totals[:expired]).to eq(0)
    end
  end

  describe "#by_field" do
    it "groups active observations by a column" do
      store.insert_observation(body: "a decision", kind: "decision", priority: 1)
      store.insert_observation(body: "another decision", kind: "decision", priority: 1)
      store.insert_observation(body: "an event", kind: "event", priority: 3)

      expect(stats.by_field(:kind)).to eq({"decision" => 2, "event" => 1})
    end
  end

  describe "#corroboration" do
    it "reports max sightings and promotable count" do
      threshold = ClaudeMemory::Domain::Observation::PROMOTION_THRESHOLD
      id = store.insert_observation(body: "seen a lot", priority: 1)
      store.increment_corroboration(id, by: threshold) # now threshold+1 sightings

      c = stats.corroboration
      expect(c[:max]).to eq(threshold + 1)
      expect(c[:promotable]).to eq(1)
    end
  end

  describe "#compression" do
    it "is nil ratio when there are no observation tokens" do
      expect(stats.compression[:ratio]).to be_nil
    end

    it "computes source/observation ratio when linked to content" do
      cid = store.upsert_content_item(
        source: "transcript",
        text_hash: "h1",
        byte_len: 400,
        raw_text: "x" * 400
      )
      store.insert_observation(body: "y" * 40, priority: 3, source_content_item_id: cid)

      comp = stats.compression
      expect(comp[:observation_tokens]).to eq(10) # 40 chars / 4
      expect(comp[:source_tokens]).to eq(100)     # 400 bytes / 4
      expect(comp[:ratio]).to eq(10.0)
    end
  end
end
