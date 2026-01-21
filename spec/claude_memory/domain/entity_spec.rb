# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Domain::Entity do
  describe "#initialize" do
    it "creates an entity with required attributes" do
      entity = described_class.new(
        id: 1,
        type: "database",
        canonical_name: "PostgreSQL",
        slug: "postgresql"
      )

      expect(entity.id).to eq(1)
      expect(entity.type).to eq("database")
      expect(entity.canonical_name).to eq("PostgreSQL")
      expect(entity.slug).to eq("postgresql")
    end

    it "accepts optional created_at" do
      entity = described_class.new(
        id: 1,
        type: "framework",
        canonical_name: "Rails",
        slug: "rails",
        created_at: "2024-01-01"
      )

      expect(entity.created_at).to eq("2024-01-01")
    end

    it "freezes the object" do
      entity = described_class.new(id: 1, type: "database", canonical_name: "MySQL", slug: "mysql")
      expect(entity).to be_frozen
    end

    it "raises error for missing type" do
      expect {
        described_class.new(id: 1, canonical_name: "test", slug: "test")
      }.to raise_error(ArgumentError, "type required")
    end

    it "raises error for missing canonical_name" do
      expect {
        described_class.new(id: 1, type: "database", slug: "test")
      }.to raise_error(ArgumentError, "canonical_name required")
    end

    it "raises error for missing slug" do
      expect {
        described_class.new(id: 1, type: "database", canonical_name: "test")
      }.to raise_error(ArgumentError, "slug required")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      entity = described_class.new(
        id: 1,
        type: "database",
        canonical_name: "PostgreSQL",
        slug: "postgresql",
        created_at: "2024-01-01"
      )

      hash = entity.to_h
      expect(hash).to eq({
        id: 1,
        type: "database",
        canonical_name: "PostgreSQL",
        slug: "postgresql",
        created_at: "2024-01-01"
      })
    end

    it "includes nil created_at when not provided" do
      entity = described_class.new(id: 1, type: "database", canonical_name: "MySQL", slug: "mysql")
      hash = entity.to_h
      expect(hash[:created_at]).to be_nil
    end
  end

  describe "type checking" do
    it "has database? method" do
      entity = described_class.new(id: 1, type: "database", canonical_name: "PostgreSQL", slug: "postgresql")
      expect(entity.database?).to be true
    end

    it "has framework? method" do
      entity = described_class.new(id: 1, type: "framework", canonical_name: "Rails", slug: "rails")
      expect(entity.framework?).to be true
    end

    it "has person? method" do
      entity = described_class.new(id: 1, type: "person", canonical_name: "Alice", slug: "alice")
      expect(entity.person?).to be true
    end

    it "returns false for non-matching type" do
      entity = described_class.new(id: 1, type: "database", canonical_name: "PostgreSQL", slug: "postgresql")
      expect(entity.framework?).to be false
      expect(entity.person?).to be false
    end
  end
end
