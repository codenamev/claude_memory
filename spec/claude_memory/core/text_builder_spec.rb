# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/text_builder"

RSpec.describe ClaudeMemory::Core::TextBuilder do
  describe ".build_searchable_text" do
    it "builds searchable text from entities, facts, and decisions" do
      entities = [
        {type: "database", name: "PostgreSQL"},
        {type: "framework", name: "Rails"}
      ]
      facts = [
        {subject: "repo", predicate: "uses_database", object: "PostgreSQL", quote: "We use Postgres"},
        {subject: "repo", predicate: "uses_framework", object: "Rails", quote: "Built with Rails"}
      ]
      decisions = [
        {title: "Use PostgreSQL", summary: "Chose PostgreSQL for reliability"}
      ]

      text = described_class.build_searchable_text(entities, facts, decisions)

      expect(text).to include("database: PostgreSQL")
      expect(text).to include("framework: Rails")
      expect(text).to include("repo uses_database PostgreSQL We use Postgres")
      expect(text).to include("repo uses_framework Rails Built with Rails")
      expect(text).to include("Use PostgreSQL Chose PostgreSQL for reliability")
    end

    it "handles empty entities" do
      text = described_class.build_searchable_text([], [], [])

      expect(text).to eq("")
    end

    it "handles only entities" do
      entities = [{type: "database", name: "MySQL"}]

      text = described_class.build_searchable_text(entities, [], [])

      expect(text).to eq("database: MySQL")
    end

    it "handles only facts" do
      facts = [{subject: "repo", predicate: "uses", object: "Ruby", quote: "Built with Ruby"}]

      text = described_class.build_searchable_text([], facts, [])

      expect(text).to eq("repo uses Ruby Built with Ruby")
    end

    it "handles only decisions" do
      decisions = [{title: "Use TDD", summary: "Test-driven development chosen"}]

      text = described_class.build_searchable_text([], [], decisions)

      expect(text).to eq("Use TDD Test-driven development chosen")
    end

    it "joins parts with single space" do
      entities = [{type: "db", name: "A"}]
      facts = [{subject: "B", predicate: "C", object: "D", quote: "E"}]
      decisions = [{title: "F", summary: "G"}]

      text = described_class.build_searchable_text(entities, facts, decisions)

      expect(text).to eq("db: A B C D E F G")
    end

    it "strips leading and trailing whitespace" do
      entities = []
      facts = [{subject: "repo", predicate: "uses", object: "Ruby", quote: ""}]

      text = described_class.build_searchable_text(entities, facts, [])

      expect(text).not_to start_with(" ")
      expect(text).not_to end_with(" ")
    end

    it "handles nil values in facts gracefully" do
      facts = [{subject: nil, predicate: "uses", object: nil, quote: "Ruby"}]

      text = described_class.build_searchable_text([], facts, [])

      expect(text).to include("uses")
      expect(text).to include("Ruby")
    end

    it "handles multiple entities of same type" do
      entities = [
        {type: "database", name: "PostgreSQL"},
        {type: "database", name: "Redis"}
      ]

      text = described_class.build_searchable_text(entities, [], [])

      expect(text).to eq("database: PostgreSQL database: Redis")
    end

    it "builds deterministic output for same input" do
      entities = [{type: "db", name: "A"}]
      facts = [{subject: "B", predicate: "C", object: "D", quote: "E"}]
      decisions = [{title: "F", summary: "G"}]

      text1 = described_class.build_searchable_text(entities, facts, decisions)
      text2 = described_class.build_searchable_text(entities, facts, decisions)

      expect(text1).to eq(text2)
    end
  end

  describe ".symbolize_keys" do
    it "converts string keys to symbols" do
      hash = {"name" => "Alice", "age" => 30}

      result = described_class.symbolize_keys(hash)

      expect(result).to eq({name: "Alice", age: 30})
    end

    it "preserves symbol keys" do
      hash = {name: "Bob", age: 25}

      result = described_class.symbolize_keys(hash)

      expect(result).to eq({name: "Bob", age: 25})
    end

    it "handles mixed string and symbol keys" do
      hash = {"name" => "Charlie", :age => 35}

      result = described_class.symbolize_keys(hash)

      expect(result).to eq({name: "Charlie", age: 35})
    end

    it "handles empty hash" do
      result = described_class.symbolize_keys({})

      expect(result).to eq({})
    end

    it "handles nested hashes (only top level)" do
      hash = {"outer" => {"inner" => "value"}}

      result = described_class.symbolize_keys(hash)

      expect(result).to eq({outer: {"inner" => "value"}})
    end

    it "preserves values unchanged" do
      hash = {"key" => [1, 2, 3], "other" => {a: 1}}

      result = described_class.symbolize_keys(hash)

      expect(result[:key]).to eq([1, 2, 3])
      expect(result[:other]).to eq({a: 1})
    end

    it "handles numeric string keys" do
      hash = {"1" => "one", "2" => "two"}

      result = described_class.symbolize_keys(hash)

      expect(result).to have_key(:"1")
      expect(result).to have_key(:"2")
      expect(result[:"1"]).to eq("one")
    end
  end
end
