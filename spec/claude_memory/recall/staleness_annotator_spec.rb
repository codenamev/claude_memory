# frozen_string_literal: true

RSpec.describe ClaudeMemory::Recall::StalenessAnnotator do
  let(:now) { Time.utc(2026, 5, 28) }
  let(:old_date) { "2024-06-01T00:00:00Z" }   # ~23 months before now
  let(:recent_date) { "2026-05-01T00:00:00Z" } # < 180d before now

  def fact(overrides = {})
    {predicate: "deployment_platform", valid_from: old_date, created_at: old_date, last_recalled_at: nil}.merge(overrides)
  end

  describe ".marker_for" do
    it "flags an old, never-confirmed single-value fact" do
      marker = described_class.marker_for(fact, now: now)
      expect(marker).to include("stale")
      expect(marker).to include("2024-06-01")
      expect(marker).to include("verify before relying")
    end

    it "returns nil for multi-value predicates even when old" do
      %w[convention decision uses_framework uses_language architecture reference].each do |pred|
        expect(described_class.marker_for(fact(predicate: pred), now: now)).to be_nil
      end
    end

    it "flags all three single-value predicates" do
      %w[uses_database deployment_platform auth_method].each do |pred|
        expect(described_class.marker_for(fact(predicate: pred), now: now)).not_to be_nil
      end
    end

    it "returns nil when the claim is recent (fresh fact about historical thing)" do
      expect(described_class.marker_for(fact(valid_from: recent_date, created_at: recent_date), now: now)).to be_nil
    end

    it "returns nil when the fact was recalled recently even if old" do
      expect(described_class.marker_for(fact(last_recalled_at: recent_date), now: now)).to be_nil
    end

    it "flags expiring facts on any predicate, with days since expiring_since" do
      f = fact(predicate: "convention", status: "expiring", expiring_since: "2026-05-18T00:00:00Z")
      marker = described_class.marker_for(f, now: now)
      expect(marker).to include("expiring")
      expect(marker).to include("10d ago")
      expect(marker).to include("reaffirm")
    end

    it "prefers the expiring marker over the heuristic stale marker" do
      marker = described_class.marker_for(fact(status: "expiring"), now: now)
      expect(marker).to include("expiring")
      expect(marker).not_to include("verify before relying")
    end

    it "does not treat active or expired statuses as expiring" do
      expect(described_class.marker_for(fact(status: "active", predicate: "convention"), now: now)).to be_nil
      expect(described_class.marker_for(fact(status: "expired", predicate: "convention"), now: now)).to be_nil
    end

    it "flags when last_recalled_at is also old" do
      expect(described_class.marker_for(fact(last_recalled_at: old_date), now: now)).not_to be_nil
    end

    it "falls back to created_at when valid_from is absent" do
      expect(described_class.marker_for(fact(valid_from: nil), now: now)).not_to be_nil
    end

    it "returns nil when no temporal anchor is present" do
      expect(described_class.marker_for(fact(valid_from: nil, created_at: nil), now: now)).to be_nil
    end

    it "respects a custom threshold" do
      # recent_date is ~27 days before now; a 14-day threshold makes it stale
      f = fact(valid_from: recent_date, created_at: recent_date)
      expect(described_class.marker_for(f, now: now, threshold_days: 14)).not_to be_nil
      expect(described_class.marker_for(f, now: now, threshold_days: 365)).to be_nil
    end

    it "accepts Time objects as well as strings" do
      expect(described_class.marker_for(fact(valid_from: Time.utc(2024, 6, 1)), now: now)).not_to be_nil
    end

    it "returns nil for an unparseable date rather than raising" do
      expect(described_class.marker_for(fact(valid_from: "not-a-date", created_at: nil), now: now)).to be_nil
    end
  end

  describe ".stale?" do
    it "mirrors marker_for presence" do
      expect(described_class.stale?(fact, now: now)).to be(true)
      expect(described_class.stale?(fact(predicate: "convention"), now: now)).to be(false)
    end
  end
end
