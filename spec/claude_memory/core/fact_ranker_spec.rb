# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::FactRanker do
  describe ".dedupe_and_sort_index" do
    it "deduplicates by fact signature" do
      results = [
        {subject: "User", predicate: "prefers", object_preview: "Ruby", source: :project},
        {subject: "User", predicate: "prefers", object_preview: "Ruby", source: :global}, # Duplicate
        {subject: "User", predicate: "likes", object_preview: "Python", source: :project}
      ]

      deduped = described_class.dedupe_and_sort_index(results, 10)

      expect(deduped.length).to eq(2)
      expect(deduped.map { |r| r[:predicate] }).to eq(["prefers", "likes"])
    end

    it "prioritizes project results over global" do
      results = [
        {subject: "App", predicate: "uses", object_preview: "Rails", source: :global},
        {subject: "User", predicate: "prefers", object_preview: "Ruby", source: :project}
      ]

      sorted = described_class.dedupe_and_sort_index(results, 10)

      expect(sorted.first[:source]).to eq(:project)
      expect(sorted.last[:source]).to eq(:global)
    end

    it "limits results to specified count" do
      results = 5.times.map do |i|
        {subject: "Item", predicate: "attr_#{i}", object_preview: "value", source: :project}
      end

      limited = described_class.dedupe_and_sort_index(results, 3)

      expect(limited.length).to eq(3)
    end

    it "handles empty results" do
      result = described_class.dedupe_and_sort_index([], 10)
      expect(result).to eq([])
    end
  end

  describe ".dedupe_and_sort" do
    let(:old_time) { "2026-01-01T12:00:00Z" }
    let(:new_time) { "2026-01-27T12:00:00Z" }

    it "deduplicates by fact signature" do
      results = [
        {fact: {subject_name: "User", predicate: "prefers", object_literal: "Ruby", created_at: old_time}, source: :project},
        {fact: {subject_name: "User", predicate: "prefers", object_literal: "Ruby", created_at: new_time}, source: :global}, # Duplicate
        {fact: {subject_name: "User", predicate: "likes", object_literal: "Python", created_at: old_time}, source: :project}
      ]

      deduped = described_class.dedupe_and_sort(results, 10)

      expect(deduped.length).to eq(2)
      expect(deduped.map { |r| r[:fact][:predicate] }).to eq(["prefers", "likes"])
    end

    it "prioritizes project results over global" do
      results = [
        {fact: {subject_name: "App", predicate: "uses", object_literal: "Rails", created_at: old_time}, source: :global},
        {fact: {subject_name: "User", predicate: "prefers", object_literal: "Ruby", created_at: old_time}, source: :project}
      ]

      sorted = described_class.dedupe_and_sort(results, 10)

      expect(sorted.first[:source]).to eq(:project)
      expect(sorted.last[:source]).to eq(:global)
    end

    it "sorts by creation time within same source" do
      results = [
        {fact: {subject_name: "User", predicate: "old", object_literal: "value", created_at: old_time}, source: :project},
        {fact: {subject_name: "User", predicate: "new", object_literal: "value", created_at: new_time}, source: :project}
      ]

      sorted = described_class.dedupe_and_sort(results, 10)

      expect(sorted.first[:fact][:predicate]).to eq("old")
      expect(sorted.last[:fact][:predicate]).to eq("new")
    end

    it "limits results to specified count" do
      results = 5.times.map do |i|
        {fact: {subject_name: "Item", predicate: "attr_#{i}", object_literal: "value", created_at: old_time}, source: :project}
      end

      limited = described_class.dedupe_and_sort(results, 3)

      expect(limited.length).to eq(3)
    end

    it "handles empty results" do
      result = described_class.dedupe_and_sort([], 10)
      expect(result).to eq([])
    end
  end

  describe ".sort_by_scope_priority" do
    let(:project_path) { "/Users/test/project" }

    it "prioritizes current project facts" do
      facts = [
        {fact: {scope: "project", project_path: "/Users/test/other"}},
        {fact: {scope: "project", project_path: project_path}},
        {fact: {scope: "global", project_path: nil}}
      ]

      sorted = described_class.sort_by_scope_priority(facts, project_path)

      expect(sorted[0][:fact][:project_path]).to eq(project_path)
    end

    it "prioritizes global over other projects" do
      facts = [
        {fact: {scope: "project", project_path: "/Users/test/other"}},
        {fact: {scope: "global", project_path: nil}}
      ]

      sorted = described_class.sort_by_scope_priority(facts, project_path)

      expect(sorted[0][:fact][:scope]).to eq("global")
      expect(sorted[1][:fact][:project_path]).to eq("/Users/test/other")
    end

    it "handles empty facts" do
      result = described_class.sort_by_scope_priority([], project_path)
      expect(result).to eq([])
    end

    it "handles nil project_path parameter" do
      facts = [
        {fact: {scope: "global", project_path: nil}},
        {fact: {scope: "project", project_path: "/Users/test/project"}}
      ]

      sorted = described_class.sort_by_scope_priority(facts, nil)

      # With nil project_path, no facts match current project
      # So global should come first
      expect(sorted[0][:fact][:scope]).to eq("global")
    end
  end

  describe ".dedupe_by_fact_id" do
    it "keeps only one result per fact_id" do
      results = [
        {fact: {id: 1, predicate: "prefers"}, similarity: 0.8},
        {fact: {id: 1, predicate: "prefers"}, similarity: 0.9}, # Higher similarity
        {fact: {id: 2, predicate: "likes"}, similarity: 0.7}
      ]

      deduped = described_class.dedupe_by_fact_id(results, 10)

      expect(deduped.length).to eq(2)
      expect(deduped.map { |r| r[:fact][:id] }).to eq([1, 2])
    end

    it "keeps result with highest similarity for each fact" do
      results = [
        {fact: {id: 1}, similarity: 0.8},
        {fact: {id: 1}, similarity: 0.9},
        {fact: {id: 1}, similarity: 0.7}
      ]

      deduped = described_class.dedupe_by_fact_id(results, 10)

      expect(deduped.length).to eq(1)
      expect(deduped.first[:similarity]).to eq(0.9)
    end

    it "sorts by similarity descending" do
      results = [
        {fact: {id: 1}, similarity: 0.7},
        {fact: {id: 2}, similarity: 0.9},
        {fact: {id: 3}, similarity: 0.5}
      ]

      sorted = described_class.dedupe_by_fact_id(results, 10)

      expect(sorted.map { |r| r[:similarity] }).to eq([0.9, 0.7, 0.5])
    end

    it "limits results to specified count" do
      results = 5.times.map do |i|
        {fact: {id: i}, similarity: 1.0 - (i * 0.1)}
      end

      limited = described_class.dedupe_by_fact_id(results, 3)

      expect(limited.length).to eq(3)
      expect(limited.map { |r| r[:fact][:id] }).to eq([0, 1, 2])
    end

    it "handles empty results" do
      result = described_class.dedupe_by_fact_id([], 10)
      expect(result).to eq([])
    end
  end
end
