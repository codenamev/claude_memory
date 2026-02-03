# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Recall::ExpansionDetector do
  describe ".strong_fts_signal?" do
    it "returns true when top result dominates" do
      # rank values are negative (more negative = better)
      ranks = [
        {content_item_id: 1, rank: -10.0},
        {content_item_id: 2, rank: -2.0},
        {content_item_id: 3, rank: -1.5}
      ]

      expect(described_class.strong_fts_signal?(ranks)).to be true
    end

    it "returns false when results are close together" do
      ranks = [
        {content_item_id: 1, rank: -5.0},
        {content_item_id: 2, rank: -4.8},
        {content_item_id: 3, rank: -4.5}
      ]

      expect(described_class.strong_fts_signal?(ranks)).to be false
    end

    it "returns false with fewer than 2 results" do
      expect(described_class.strong_fts_signal?([{content_item_id: 1, rank: -10.0}])).to be false
    end

    it "returns false with nil input" do
      expect(described_class.strong_fts_signal?(nil)).to be false
    end

    it "returns false with empty array" do
      expect(described_class.strong_fts_signal?([])).to be false
    end

    it "returns false when max score is zero" do
      ranks = [
        {content_item_id: 1, rank: 0.0},
        {content_item_id: 2, rank: 0.0}
      ]

      expect(described_class.strong_fts_signal?(ranks)).to be false
    end

    it "detects exact keyword match" do
      # Simulates FTS5 where exact match gets much better rank
      ranks = [
        {content_item_id: 1, rank: -8.5},
        {content_item_id: 2, rank: -1.0},
        {content_item_id: 3, rank: -0.8}
      ]

      expect(described_class.strong_fts_signal?(ranks)).to be true
    end

    it "returns false for broad queries with even distribution" do
      ranks = [
        {content_item_id: 1, rank: -3.0},
        {content_item_id: 2, rank: -2.8},
        {content_item_id: 3, rank: -2.5},
        {content_item_id: 4, rank: -2.3}
      ]

      expect(described_class.strong_fts_signal?(ranks)).to be false
    end
  end
end
