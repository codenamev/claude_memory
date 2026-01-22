# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Index::IndexQueryLogic do
  describe ".collect_fact_ids" do
    it "collects fact IDs from provenance records in content order" do
      # Simulated batch query result grouped by content_item_id
      provenance_by_content = {
        101 => [{fact_id: 1}, {fact_id: 2}],
        102 => [{fact_id: 3}],
        103 => [{fact_id: 4}, {fact_id: 5}, {fact_id: 6}]
      }

      content_ids = [101, 102, 103]
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result).to eq([1, 2, 3, 4, 5, 6])
    end

    it "respects content order (FTS relevance)" do
      provenance_by_content = {
        101 => [{fact_id: 10}],
        102 => [{fact_id: 20}],
        103 => [{fact_id: 30}]
      }

      # Content order: 102, 101, 103 (FTS determined relevance)
      content_ids = [102, 101, 103]
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      # Should follow content order, not fact ID order
      expect(result).to eq([20, 10, 30])
    end

    it "deduplicates fact IDs" do
      provenance_by_content = {
        101 => [{fact_id: 1}, {fact_id: 2}],
        102 => [{fact_id: 2}, {fact_id: 3}], # fact 2 appears again
        103 => [{fact_id: 1}] # fact 1 appears again
      }

      content_ids = [101, 102, 103]
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      # Should only include each fact once, in first-seen order
      expect(result).to eq([1, 2, 3])
    end

    it "respects limit" do
      provenance_by_content = {
        101 => [{fact_id: 1}, {fact_id: 2}, {fact_id: 3}],
        102 => [{fact_id: 4}, {fact_id: 5}],
        103 => [{fact_id: 6}, {fact_id: 7}, {fact_id: 8}]
      }

      content_ids = [101, 102, 103]
      limit = 5

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result.size).to eq(5)
      expect(result).to eq([1, 2, 3, 4, 5])
    end

    it "stops processing content items after reaching limit" do
      provenance_by_content = {
        101 => [{fact_id: 1}, {fact_id: 2}],
        102 => [{fact_id: 3}, {fact_id: 4}],
        103 => [{fact_id: 5}, {fact_id: 6}]
      }

      content_ids = [101, 102, 103]
      limit = 3

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      # Should stop after content 102 (reaches limit of 3)
      expect(result).to eq([1, 2, 3])
    end

    it "handles content with no provenance records" do
      provenance_by_content = {
        101 => [{fact_id: 1}],
        102 => [], # no provenance
        103 => [{fact_id: 2}]
      }

      content_ids = [101, 102, 103]
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result).to eq([1, 2])
    end

    it "handles missing content IDs in provenance map" do
      provenance_by_content = {
        101 => [{fact_id: 1}],
        # 102 is missing
        103 => [{fact_id: 2}]
      }

      content_ids = [101, 102, 103]
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result).to eq([1, 2])
    end

    it "returns empty array when no provenance" do
      provenance_by_content = {}
      content_ids = [101, 102]
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result).to eq([])
    end

    it "returns empty array when no content IDs" do
      provenance_by_content = {
        101 => [{fact_id: 1}]
      }
      content_ids = []
      limit = 10

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result).to eq([])
    end

    it "handles limit of zero" do
      provenance_by_content = {
        101 => [{fact_id: 1}, {fact_id: 2}]
      }
      content_ids = [101]
      limit = 0

      result = described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(result).to eq([])
    end

    it "does not mutate input data" do
      provenance_by_content = {
        101 => [{fact_id: 1}]
      }
      content_ids = [101]
      limit = 10

      original_provenance = provenance_by_content.dup
      original_content_ids = content_ids.dup

      described_class.collect_fact_ids(provenance_by_content, content_ids, limit)

      expect(provenance_by_content).to eq(original_provenance)
      expect(content_ids).to eq(original_content_ids)
    end
  end
end
