# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/result_sorter"

RSpec.describe ClaudeMemory::Core::ResultSorter do
  describe ".sort_by_timestamp" do
    it "sorts results by created_at descending (most recent first)" do
      results = [
        {id: 1, created_at: Time.new(2024, 1, 1)},
        {id: 3, created_at: Time.new(2024, 1, 3)},
        {id: 2, created_at: Time.new(2024, 1, 2)}
      ]

      sorted = described_class.sort_by_timestamp(results, 10)

      expect(sorted.map { |r| r[:id] }).to eq([3, 2, 1])
    end

    it "applies limit to sorted results" do
      results = [
        {id: 1, created_at: Time.new(2024, 1, 1)},
        {id: 2, created_at: Time.new(2024, 1, 2)},
        {id: 3, created_at: Time.new(2024, 1, 3)},
        {id: 4, created_at: Time.new(2024, 1, 4)},
        {id: 5, created_at: Time.new(2024, 1, 5)}
      ]

      sorted = described_class.sort_by_timestamp(results, 3)

      expect(sorted.length).to eq(3)
      expect(sorted.map { |r| r[:id] }).to eq([5, 4, 3])
    end

    it "handles limit larger than result count" do
      results = [
        {id: 1, created_at: Time.new(2024, 1, 1)},
        {id: 2, created_at: Time.new(2024, 1, 2)}
      ]

      sorted = described_class.sort_by_timestamp(results, 10)

      expect(sorted.length).to eq(2)
      expect(sorted.map { |r| r[:id] }).to eq([2, 1])
    end

    it "handles empty array" do
      sorted = described_class.sort_by_timestamp([], 10)

      expect(sorted).to eq([])
    end

    it "handles limit of zero" do
      results = [
        {id: 1, created_at: Time.new(2024, 1, 1)},
        {id: 2, created_at: Time.new(2024, 1, 2)}
      ]

      sorted = described_class.sort_by_timestamp(results, 0)

      expect(sorted).to eq([])
    end

    it "handles results with same timestamp" do
      same_time = Time.new(2024, 1, 1)
      results = [
        {id: 1, created_at: same_time},
        {id: 2, created_at: same_time},
        {id: 3, created_at: same_time}
      ]

      sorted = described_class.sort_by_timestamp(results, 10)

      expect(sorted.length).to eq(3)
      # All have same timestamp, so order is stable
    end

    it "handles DateTime objects" do
      results = [
        {id: 1, created_at: DateTime.new(2024, 1, 1)},
        {id: 2, created_at: DateTime.new(2024, 1, 2)},
        {id: 3, created_at: DateTime.new(2024, 1, 3)}
      ]

      sorted = described_class.sort_by_timestamp(results, 10)

      expect(sorted.map { |r| r[:id] }).to eq([3, 2, 1])
    end

    it "handles integer timestamps (Unix epoch)" do
      results = [
        {id: 1, created_at: 1000},
        {id: 2, created_at: 3000},
        {id: 3, created_at: 2000}
      ]

      sorted = described_class.sort_by_timestamp(results, 10)

      expect(sorted.map { |r| r[:id] }).to eq([2, 3, 1])
    end

    it "preserves other fields in results" do
      results = [
        {id: 1, created_at: Time.new(2024, 1, 1), name: "First", value: 100},
        {id: 2, created_at: Time.new(2024, 1, 2), name: "Second", value: 200}
      ]

      sorted = described_class.sort_by_timestamp(results, 10)

      expect(sorted[0][:name]).to eq("Second")
      expect(sorted[0][:value]).to eq(200)
      expect(sorted[1][:name]).to eq("First")
      expect(sorted[1][:value]).to eq(100)
    end
  end

  describe ".annotate_source" do
    it "adds source to each result" do
      results = [
        {id: 1, predicate: "uses"},
        {id: 2, predicate: "prefers"}
      ]

      described_class.annotate_source(results, :project)

      expect(results[0][:source]).to eq(:project)
      expect(results[1][:source]).to eq(:project)
    end

    it "overwrites existing source" do
      results = [
        {id: 1, source: :old}
      ]

      described_class.annotate_source(results, :new)

      expect(results[0][:source]).to eq(:new)
    end

    it "handles empty array" do
      results = []

      described_class.annotate_source(results, :project)

      expect(results).to eq([])
    end

    it "handles different source symbols" do
      results = [{id: 1}]

      described_class.annotate_source(results, :global)

      expect(results[0][:source]).to eq(:global)
    end

    it "mutates original array in place" do
      results = [{id: 1}, {id: 2}]
      original_object_ids = results.map(&:object_id)

      described_class.annotate_source(results, :project)

      expect(results.map(&:object_id)).to eq(original_object_ids)
      expect(results[0][:source]).to eq(:project)
      expect(results[1][:source]).to eq(:project)
    end

    it "returns the mutated array" do
      results = [{id: 1}]

      return_value = described_class.annotate_source(results, :project)

      expect(return_value).to equal(results)
    end

    it "preserves other fields" do
      results = [
        {id: 1, predicate: "uses", object_literal: "Ruby"}
      ]

      described_class.annotate_source(results, :project)

      expect(results[0][:id]).to eq(1)
      expect(results[0][:predicate]).to eq("uses")
      expect(results[0][:object_literal]).to eq("Ruby")
      expect(results[0][:source]).to eq(:project)
    end
  end
end
