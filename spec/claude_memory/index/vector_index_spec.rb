# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe ClaudeMemory::Index::VectorIndex do
  let(:db_path) { File.join(Dir.mktmpdir, "test_vec.db") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:vec_index) { described_class.new(store) }

  after do
    store.close
    File.unlink(db_path) if File.exist?(db_path)
  end

  # Helper to create a random 384-dim vector
  def random_vector(dimensions = 384)
    Array.new(dimensions) { rand(-1.0..1.0) }
  end

  # Helper to create a normalized vector
  def normalized_vector(dimensions = 384)
    vec = random_vector(dimensions)
    norm = Math.sqrt(vec.sum { |v| v * v })
    vec.map { |v| v / norm }
  end

  describe "#available?" do
    it "returns true when sqlite-vec extension is loadable" do
      expect(vec_index.available?).to be true
    end

    it "caches the result" do
      vec_index.available?
      # Second call should use cached value
      expect(vec_index.available?).to be true
    end
  end

  describe "#insert_embedding" do
    it "inserts an embedding into the vec0 table" do
      skip "sqlite-vec not available" unless vec_index.available?

      vector = normalized_vector
      entity_id = store.find_or_create_entity(type: "repo", name: "test")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "rails"
      )

      result = vec_index.insert_embedding(fact_id, vector)
      expect(result).to be true
      expect(vec_index.count).to eq(1)

      # Verify vec_indexed_at is set
      fact = store.facts.where(id: fact_id).first
      expect(fact[:vec_indexed_at]).not_to be_nil
    end

    it "replaces existing embedding for same fact_id" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "rails"
      )

      vec_index.insert_embedding(fact_id, normalized_vector)
      vec_index.insert_embedding(fact_id, normalized_vector)
      expect(vec_index.count).to eq(1)
    end
  end

  describe "#remove_embedding" do
    it "removes an embedding from the vec0 table" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "uses_framework",
        object_literal: "rails"
      )

      vec_index.insert_embedding(fact_id, normalized_vector)
      expect(vec_index.count).to eq(1)

      vec_index.remove_embedding(fact_id)
      expect(vec_index.count).to eq(0)

      # Verify vec_indexed_at is cleared
      fact = store.facts.where(id: fact_id).first
      expect(fact[:vec_indexed_at]).to be_nil
    end
  end

  describe "#search" do
    it "returns nearest neighbors sorted by distance" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")

      # Insert several facts with distinct embeddings
      vectors = {}
      5.times do |i|
        fact_id = store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "fact_#{i}"
        )
        vec = normalized_vector
        vectors[fact_id] = vec
        vec_index.insert_embedding(fact_id, vec)
      end

      # Search with one of the stored vectors (should find exact match)
      target_id, target_vec = vectors.first
      results = vec_index.search(target_vec, k: 3)

      expect(results).not_to be_empty
      expect(results.length).to be <= 3

      # First result should be the exact match (highest similarity)
      expect(results.first[:fact_id]).to eq(target_id)
      expect(results.first[:similarity]).to be_within(0.01).of(1.0)

      # All results should have distance and similarity
      results.each do |r|
        expect(r).to have_key(:fact_id)
        expect(r).to have_key(:distance)
        expect(r).to have_key(:similarity)
        expect(r[:similarity]).to be_between(0.0, 1.0).inclusive
      end
    end

    it "returns empty array when no embeddings exist" do
      skip "sqlite-vec not available" unless vec_index.available?

      results = vec_index.search(normalized_vector, k: 5)
      expect(results).to eq([])
    end

    it "respects the k parameter" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")

      10.times do |i|
        fact_id = store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "fact_#{i}"
        )
        vec_index.insert_embedding(fact_id, normalized_vector)
      end

      results = vec_index.search(normalized_vector, k: 3)
      expect(results.length).to eq(3)
    end
  end

  describe "#backfill_batch!" do
    it "populates vec0 from existing embedding_json" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")

      # Create facts with embedding_json but no vec_indexed_at
      3.times do |i|
        fact_id = store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "fact_#{i}"
        )
        store.update_fact_embedding(fact_id, normalized_vector)
      end

      count = vec_index.backfill_batch!(limit: 10)

      expect(count).to eq(3)
      expect(vec_index.count).to eq(3)

      # Check vec_indexed_at is set
      unindexed = store.facts.where(vec_indexed_at: nil).where(Sequel.~(embedding_json: nil)).count
      expect(unindexed).to eq(0)
    end

    it "skips facts without embedding_json" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")
      store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "no_embedding"
      )

      count = vec_index.backfill_batch!(limit: 10)
      expect(count).to eq(0)
    end

    it "skips facts already indexed" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "already_indexed"
      )
      store.update_fact_embedding(fact_id, normalized_vector)

      # First backfill
      vec_index.backfill_batch!(limit: 10)

      # Second backfill should find nothing
      count = vec_index.backfill_batch!(limit: 10)
      expect(count).to eq(0)
    end

    it "respects limit parameter" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")

      5.times do |i|
        fact_id = store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "fact_#{i}"
        )
        store.update_fact_embedding(fact_id, normalized_vector)
      end

      count = vec_index.backfill_batch!(limit: 2)
      expect(count).to eq(2)
      expect(vec_index.count).to eq(2)
    end

    it "skips superseded facts" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "old_fact",
        status: "superseded"
      )
      store.update_fact_embedding(fact_id, normalized_vector)

      count = vec_index.backfill_batch!(limit: 10)
      expect(count).to eq(0)
    end
  end

  describe "#count" do
    it "returns 0 when empty" do
      skip "sqlite-vec not available" unless vec_index.available?

      expect(vec_index.count).to eq(0)
    end

    it "returns correct count after inserts" do
      skip "sqlite-vec not available" unless vec_index.available?

      entity_id = store.find_or_create_entity(type: "repo", name: "test")

      3.times do |i|
        fact_id = store.insert_fact(
          subject_entity_id: entity_id,
          predicate: "convention",
          object_literal: "fact_#{i}"
        )
        vec_index.insert_embedding(fact_id, normalized_vector)
      end

      expect(vec_index.count).to eq(3)
    end
  end

  context "when sqlite-vec is not available" do
    let(:unavailable_index) do
      idx = described_class.new(store)
      # Force unavailable state
      idx.instance_variable_set(:@available, false)
      idx
    end

    it "#insert_embedding returns false" do
      expect(unavailable_index.insert_embedding(1, normalized_vector)).to be false
    end

    it "#remove_embedding returns false" do
      expect(unavailable_index.remove_embedding(1)).to be false
    end

    it "#search returns empty array" do
      expect(unavailable_index.search(normalized_vector)).to eq([])
    end

    it "#backfill_batch! returns 0" do
      expect(unavailable_index.backfill_batch!).to eq(0)
    end

    it "#count returns 0" do
      expect(unavailable_index.count).to eq(0)
    end
  end

  describe "#table_dimensions and #recreate! (issue #7, Finding 1)" do
    def seed_fact(object = "rails")
      entity_id = store.find_or_create_entity(type: "repo", name: "test-#{object}")
      store.insert_fact(subject_entity_id: entity_id, predicate: "uses_framework", object_literal: object)
    end

    it "reports nil before the table exists, then the created width" do
      skip "sqlite-vec not available" unless vec_index.available?

      expect(vec_index.table_dimensions).to be_nil
      vec_index.insert_embedding(seed_fact, normalized_vector(384))
      expect(vec_index.table_dimensions).to eq(384)
    end

    it "rebuilds facts_vec at a new width so a different-dim model can be adopted" do
      skip "sqlite-vec not available" unless vec_index.available?

      fact_id = seed_fact
      vec_index.insert_embedding(fact_id, normalized_vector(384))
      expect(vec_index.table_dimensions).to eq(384)

      expect(vec_index.recreate!(768)).to be true
      expect(vec_index.table_dimensions).to eq(768)
      expect(vec_index.count).to eq(0) # rebuilt empty

      # a 768-dim insert now succeeds where the 384 table would have raised
      # "Expected 384 dimensions but received 768"
      expect(vec_index.insert_embedding(fact_id, normalized_vector(768))).to be true
      expect(vec_index.count).to eq(1)
    end
  end
end
