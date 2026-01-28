# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/embedding_candidate_builder"

RSpec.describe ClaudeMemory::Core::EmbeddingCandidateBuilder do
  describe ".build_candidates" do
    it "builds candidates from fact rows with valid embeddings" do
      facts_data = [
        {
          id: 1,
          embedding_json: "[0.1, 0.2, 0.3]",
          subject_entity_id: 10,
          predicate: "uses",
          object_literal: "Ruby",
          scope: "project"
        },
        {
          id: 2,
          embedding_json: "[0.4, 0.5, 0.6]",
          subject_entity_id: 20,
          predicate: "prefers",
          object_literal: "TDD",
          scope: "global"
        }
      ]

      candidates = described_class.build_candidates(facts_data)

      expect(candidates.length).to eq(2)
      expect(candidates[0][:fact_id]).to eq(1)
      expect(candidates[0][:embedding]).to eq([0.1, 0.2, 0.3])
      expect(candidates[0][:subject_entity_id]).to eq(10)
      expect(candidates[0][:predicate]).to eq("uses")
      expect(candidates[0][:object_literal]).to eq("Ruby")
      expect(candidates[0][:scope]).to eq("project")

      expect(candidates[1][:fact_id]).to eq(2)
      expect(candidates[1][:embedding]).to eq([0.4, 0.5, 0.6])
    end

    it "removes candidates with invalid JSON" do
      facts_data = [
        {
          id: 1,
          embedding_json: "[0.1, 0.2]",
          subject_entity_id: 10,
          predicate: "uses",
          object_literal: "Ruby",
          scope: "project"
        },
        {
          id: 2,
          embedding_json: "invalid json {",
          subject_entity_id: 20,
          predicate: "prefers",
          object_literal: "TDD",
          scope: "global"
        },
        {
          id: 3,
          embedding_json: "[0.7, 0.8]",
          subject_entity_id: 30,
          predicate: "likes",
          object_literal: "Rails",
          scope: "project"
        }
      ]

      candidates = described_class.build_candidates(facts_data)

      expect(candidates.length).to eq(2)
      expect(candidates[0][:fact_id]).to eq(1)
      expect(candidates[1][:fact_id]).to eq(3)
    end

    it "handles empty array" do
      candidates = described_class.build_candidates([])

      expect(candidates).to eq([])
    end

    it "handles all invalid JSON" do
      facts_data = [
        {id: 1, embedding_json: "invalid"},
        {id: 2, embedding_json: "{broken}"}
      ]

      candidates = described_class.build_candidates(facts_data)

      expect(candidates).to eq([])
    end

    it "preserves order of valid candidates" do
      facts_data = [
        {id: 3, embedding_json: "[0.3]", predicate: "uses", object_literal: "C", scope: "project"},
        {id: 1, embedding_json: "[0.1]", predicate: "uses", object_literal: "A", scope: "project"},
        {id: 2, embedding_json: "[0.2]", predicate: "uses", object_literal: "B", scope: "project"}
      ]

      candidates = described_class.build_candidates(facts_data)

      expect(candidates.map { |c| c[:fact_id] }).to eq([3, 1, 2])
    end

    it "handles empty embedding arrays" do
      facts_data = [
        {id: 1, embedding_json: "[]", predicate: "uses", object_literal: "Ruby", scope: "project"}
      ]

      candidates = described_class.build_candidates(facts_data)

      expect(candidates.length).to eq(1)
      expect(candidates[0][:embedding]).to eq([])
    end

    it "handles large embeddings" do
      large_embedding = (1..1536).map { |i| i * 0.001 }
      facts_data = [
        {
          id: 1,
          embedding_json: large_embedding.to_json,
          predicate: "uses",
          object_literal: "Ruby",
          scope: "project"
        }
      ]

      candidates = described_class.build_candidates(facts_data)

      expect(candidates.length).to eq(1)
      expect(candidates[0][:embedding].length).to eq(1536)
      expect(candidates[0][:embedding].first).to eq(0.001)
    end
  end

  describe ".parse_candidate" do
    it "parses valid fact row into candidate" do
      row = {
        id: 42,
        embedding_json: "[0.1, 0.2, 0.3]",
        subject_entity_id: 100,
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        scope: "project"
      }

      candidate = described_class.parse_candidate(row)

      expect(candidate[:fact_id]).to eq(42)
      expect(candidate[:embedding]).to eq([0.1, 0.2, 0.3])
      expect(candidate[:subject_entity_id]).to eq(100)
      expect(candidate[:predicate]).to eq("uses_database")
      expect(candidate[:object_literal]).to eq("PostgreSQL")
      expect(candidate[:scope]).to eq("project")
    end

    it "returns nil for invalid JSON" do
      row = {
        id: 1,
        embedding_json: "not valid json",
        predicate: "uses",
        object_literal: "Ruby",
        scope: "project"
      }

      candidate = described_class.parse_candidate(row)

      expect(candidate).to be_nil
    end

    it "returns nil for malformed JSON" do
      row = {
        id: 1,
        embedding_json: "[0.1, 0.2,",
        predicate: "uses",
        object_literal: "Ruby",
        scope: "project"
      }

      candidate = described_class.parse_candidate(row)

      expect(candidate).to be_nil
    end

    it "handles nil subject_entity_id" do
      row = {
        id: 1,
        embedding_json: "[0.1]",
        subject_entity_id: nil,
        predicate: "convention",
        object_literal: "4-space indent",
        scope: "global"
      }

      candidate = described_class.parse_candidate(row)

      expect(candidate[:fact_id]).to eq(1)
      expect(candidate[:subject_entity_id]).to be_nil
      expect(candidate[:predicate]).to eq("convention")
    end

    it "handles missing optional fields" do
      row = {
        id: 1,
        embedding_json: "[0.1]"
      }

      candidate = described_class.parse_candidate(row)

      expect(candidate[:fact_id]).to eq(1)
      expect(candidate[:embedding]).to eq([0.1])
      expect(candidate[:subject_entity_id]).to be_nil
      expect(candidate[:predicate]).to be_nil
      expect(candidate[:object_literal]).to be_nil
      expect(candidate[:scope]).to be_nil
    end
  end
end
