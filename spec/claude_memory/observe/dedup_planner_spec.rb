# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Observe::DedupPlanner do
  # A stub matcher keeps this a pure, DB-free unit test of the clustering
  # algorithm — no store, no disk.
  def matcher(&block)
    Class.new do
      define_method(:similar?) { |a, b| block.call(a, b) }
    end.new
  end

  def obs(id, body, observed_at:, corroboration: 1)
    {id: id, body: body, observed_at: observed_at, corroboration_count: corroboration}
  end

  let(:always) { matcher { |_a, _b| true } }
  let(:never) { matcher { |_a, _b| false } }
  let(:by_prefix) { matcher { |a, b| a[0, 3] == b[0, 3] } }

  it "returns no folds for fewer than two rows" do
    plan = described_class.new(always).plan([obs(1, "x", observed_at: "2026-01-01")])
    expect(plan).to eq([])
  end

  it "folds older duplicates into the newest keeper" do
    rows = [
      obs(1, "use sqlite", observed_at: "2026-01-01", corroboration: 2),
      obs(2, "use sqlite", observed_at: "2026-01-03")
    ]
    plan = described_class.new(always).plan(rows)

    expect(plan.size).to eq(1)
    fold = plan.first
    expect(fold.keeper_id).to eq(2) # newest observed_at wins
    expect(fold.loser_id).to eq(1)
    expect(fold.corroboration).to eq(2) # carries the loser's sighting count
  end

  it "produces no folds when nothing is similar" do
    rows = [
      obs(1, "alpha", observed_at: "2026-01-01"),
      obs(2, "beta", observed_at: "2026-01-02")
    ]
    expect(described_class.new(never).plan(rows)).to eq([])
  end

  it "does not re-fold an observation already folded into a keeper" do
    rows = [
      obs(1, "foobar", observed_at: "2026-01-01"),
      obs(2, "foobaz", observed_at: "2026-01-02"),
      obs(3, "fooqux", observed_at: "2026-01-03")
    ]
    # All share the "foo" prefix, so the newest (3) is the sole keeper and
    # 1 + 2 fold into it — each loser folds exactly once.
    plan = described_class.new(by_prefix).plan(rows)

    expect(plan.map(&:keeper_id)).to all(eq(3))
    expect(plan.map(&:loser_id).sort).to eq([1, 2])
  end

  it "is pure — issues no store calls (no store is even available)" do
    # The absence of a store argument is the contract: planning never touches I/O.
    expect(described_class.instance_method(:plan).arity).to eq(1)
  end
end
