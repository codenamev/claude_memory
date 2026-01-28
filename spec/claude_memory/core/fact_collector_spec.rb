# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/fact_collector"

RSpec.describe ClaudeMemory::Core::FactCollector do
  describe ".collect_ordered_fact_ids" do
    it "maintains content order when collecting fact IDs" do
      provenance_by_content = {
        1 => [{fact_id: 10}, {fact_id: 11}],
        2 => [{fact_id: 20}],
        3 => [{fact_id: 30}, {fact_id: 31}]
      }
      content_ids = [1, 2, 3]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 10)

      expect(result).to eq([10, 11, 20, 30, 31])
    end

    it "deduplicates fact IDs across content items" do
      provenance_by_content = {
        1 => [{fact_id: 10}, {fact_id: 11}],
        2 => [{fact_id: 10}],  # Duplicate
        3 => [{fact_id: 12}]
      }
      content_ids = [1, 2, 3]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 10)

      expect(result).to eq([10, 11, 12])
    end

    it "respects limit parameter" do
      provenance_by_content = {
        1 => [{fact_id: 10}, {fact_id: 11}],
        2 => [{fact_id: 20}, {fact_id: 21}],
        3 => [{fact_id: 30}, {fact_id: 31}]
      }
      content_ids = [1, 2, 3]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 3)

      expect(result).to eq([10, 11, 20])
    end

    it "stops processing content items after reaching limit" do
      provenance_by_content = {
        1 => [{fact_id: 10}, {fact_id: 11}],
        2 => [{fact_id: 20}],
        3 => [{fact_id: 30}]  # Should not be processed
      }
      content_ids = [1, 2, 3]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 3)

      expect(result).to eq([10, 11, 20])
    end

    it "handles missing content in provenance map" do
      provenance_by_content = {
        1 => [{fact_id: 10}]
        # content_id 2 missing
      }
      content_ids = [1, 2, 3]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 10)

      expect(result).to eq([10])
    end

    it "handles empty provenance for content" do
      provenance_by_content = {
        1 => [{fact_id: 10}],
        2 => [],  # Empty
        3 => [{fact_id: 30}]
      }
      content_ids = [1, 2, 3]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 10)

      expect(result).to eq([10, 30])
    end

    it "handles empty content_ids" do
      provenance_by_content = {
        1 => [{fact_id: 10}]
      }

      result = described_class.collect_ordered_fact_ids(provenance_by_content, [], 10)

      expect(result).to eq([])
    end

    it "handles empty provenance map" do
      result = described_class.collect_ordered_fact_ids({}, [1, 2, 3], 10)

      expect(result).to eq([])
    end

    it "handles limit of zero" do
      provenance_by_content = {
        1 => [{fact_id: 10}]
      }
      content_ids = [1]

      result = described_class.collect_ordered_fact_ids(provenance_by_content, content_ids, 0)

      expect(result).to eq([])
    end
  end

  describe ".extract_fact_ids" do
    it "extracts fact IDs from provenance records" do
      records = [
        {fact_id: 10, content_item_id: 1},
        {fact_id: 20, content_item_id: 2},
        {fact_id: 30, content_item_id: 3}
      ]

      result = described_class.extract_fact_ids(records)

      expect(result).to eq([10, 20, 30])
    end

    it "removes duplicates" do
      records = [
        {fact_id: 10},
        {fact_id: 20},
        {fact_id: 10}  # Duplicate
      ]

      result = described_class.extract_fact_ids(records)

      expect(result).to eq([10, 20])
    end

    it "handles empty array" do
      result = described_class.extract_fact_ids([])

      expect(result).to eq([])
    end
  end

  describe ".extract_content_ids" do
    it "extracts content IDs from provenance records" do
      records = [
        {fact_id: 10, content_item_id: 1},
        {fact_id: 20, content_item_id: 2},
        {fact_id: 30, content_item_id: 3}
      ]

      result = described_class.extract_content_ids(records)

      expect(result).to eq([1, 2, 3])
    end

    it "removes duplicates" do
      records = [
        {content_item_id: 1},
        {content_item_id: 2},
        {content_item_id: 1}  # Duplicate
      ]

      result = described_class.extract_content_ids(records)

      expect(result).to eq([1, 2])
    end

    it "handles empty array" do
      result = described_class.extract_content_ids([])

      expect(result).to eq([])
    end
  end
end
