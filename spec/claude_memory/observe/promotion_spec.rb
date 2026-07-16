# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe ClaudeMemory::Observe::Promotion do
  let(:db_path) { File.join(Dir.tmpdir, "promotion_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:threshold) { ClaudeMemory::Domain::Observation::PROMOTION_THRESHOLD }
  subject(:promotion) { described_class.new(store, scope: "project") }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def seed(corroboration:, promoted: false)
    id = store.insert_observation(body: "use SQLite for storage", kind: "decision", priority: 1)
    store.increment_corroboration(id, by: corroboration - 1) if corroboration > 1
    store.mark_observation_promoted(id, fact_id: 999) if promoted
    id
  end

  it "promotes a corroborated observation into a fact" do
    id = seed(corroboration: threshold)
    result = promotion.call(observation_id: id, predicate: "decision", object: "uses SQLite because embedded")

    expect(result).to be_success
    expect(result.fact_id).to be_a(Integer)
    expect(result.corroboration_count).to eq(threshold)
    expect(store.observations.where(id: id).get(:promoted_fact_id)).to eq(result.fact_id)
    expect(store.facts.where(id: result.fact_id).get(:object_literal)).to include("SQLite")
  end

  it "refuses when required fields are missing" do
    id = seed(corroboration: threshold)
    expect(promotion.call(observation_id: id, predicate: "decision", object: "").error).to match(/required/i)
  end

  it "refuses an under-corroborated observation (anti-hallucination gate)" do
    id = seed(corroboration: 1)
    result = promotion.call(observation_id: id, predicate: "decision", object: "x")
    expect(result).not_to be_success
    expect(result.error).to match(/not yet corroborated/i)
    expect(store.observations.where(id: id).get(:promoted_at)).to be_nil
  end

  it "refuses a missing observation" do
    expect(promotion.call(observation_id: 9999, predicate: "decision", object: "x").error).to match(/not found/i)
  end

  it "refuses an already-promoted observation" do
    id = seed(corroboration: threshold, promoted: true)
    expect(promotion.call(observation_id: id, predicate: "decision", object: "x").error).to match(/already promoted/i)
  end
end
