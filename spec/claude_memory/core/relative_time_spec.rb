# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/relative_time"

RSpec.describe ClaudeMemory::Core::RelativeTime do
  let(:now) { Time.new(2026, 2, 2, 12, 0, 0, "+00:00") }

  describe ".format" do
    it "returns 'just now' for timestamps within the last minute" do
      expect(described_class.format(now - 5, now: now)).to eq("just now")
      expect(described_class.format(now - 30, now: now)).to eq("just now")
      expect(described_class.format(now, now: now)).to eq("just now")
    end

    it "returns minutes for timestamps within the last hour" do
      expect(described_class.format(now - 60, now: now)).to eq("1m ago")
      expect(described_class.format(now - 120, now: now)).to eq("2m ago")
      expect(described_class.format(now - 3540, now: now)).to eq("59m ago")
    end

    it "returns hours for timestamps within the last day" do
      expect(described_class.format(now - 3600, now: now)).to eq("1h ago")
      expect(described_class.format(now - 7200, now: now)).to eq("2h ago")
      expect(described_class.format(now - 82800, now: now)).to eq("23h ago")
    end

    it "returns days for timestamps within the last week" do
      expect(described_class.format(now - 86400, now: now)).to eq("1d ago")
      expect(described_class.format(now - 172800, now: now)).to eq("2d ago")
      expect(described_class.format(now - 518400, now: now)).to eq("6d ago")
    end

    it "returns absolute date for timestamps older than a week" do
      expect(described_class.format(now - 604800, now: now)).to eq("2026-01-26")
      expect(described_class.format(now - 2592000, now: now)).to eq("2026-01-03")
    end

    it "returns absolute date for future timestamps" do
      expect(described_class.format(now + 3600, now: now)).to eq("2026-02-02")
    end

    it "handles ISO 8601 string timestamps" do
      expect(described_class.format("2026-02-02T11:59:00+00:00", now: now)).to eq("1m ago")
    end

    it "handles Time objects" do
      expect(described_class.format(now - 300, now: now)).to eq("5m ago")
    end

    it "handles integer (epoch) timestamps" do
      epoch = now.to_i - 7200
      expect(described_class.format(epoch, now: now)).to eq("2h ago")
    end

    it "handles float (epoch) timestamps" do
      epoch = now.to_f - 120.5
      expect(described_class.format(epoch, now: now)).to eq("2m ago")
    end

    it "returns nil for nil input" do
      expect(described_class.format(nil, now: now)).to be_nil
    end

    it "returns nil for unparseable strings" do
      expect(described_class.format("not a date", now: now)).to be_nil
    end
  end

  describe ".parse_time" do
    it "passes through Time objects" do
      time = Time.now
      expect(described_class.parse_time(time)).to equal(time)
    end

    it "parses ISO 8601 strings" do
      result = described_class.parse_time("2026-01-15T10:30:00Z")
      expect(result).to be_a(Time)
      expect(result.year).to eq(2026)
    end

    it "converts integers to Time via Time.at" do
      result = described_class.parse_time(1738483200)
      expect(result).to be_a(Time)
    end

    it "returns nil for invalid strings" do
      expect(described_class.parse_time("garbage")).to be_nil
    end
  end
end
