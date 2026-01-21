# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Domain::Fact do
  describe "#initialize" do
    it "creates a fact with required attributes" do
      fact = described_class.new(
        id: 1,
        subject_name: "repo",
        predicate: "uses_database",
        object_literal: "PostgreSQL"
      )

      expect(fact.id).to eq(1)
      expect(fact.subject_name).to eq("repo")
      expect(fact.predicate).to eq("uses_database")
      expect(fact.object_literal).to eq("PostgreSQL")
    end

    it "sets default status to active" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value")
      expect(fact.status).to eq("active")
    end

    it "sets default confidence to 1.0" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value")
      expect(fact.confidence).to eq(1.0)
    end

    it "sets default scope to project" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value")
      expect(fact.scope).to eq("project")
    end

    it "accepts optional attributes" do
      fact = described_class.new(
        id: 1,
        predicate: "test",
        object_literal: "value",
        status: "superseded",
        confidence: 0.8,
        scope: "global",
        project_path: "/path/to/project",
        valid_from: "2024-01-01",
        valid_to: "2024-12-31",
        created_at: "2024-01-01"
      )

      expect(fact.status).to eq("superseded")
      expect(fact.confidence).to eq(0.8)
      expect(fact.scope).to eq("global")
      expect(fact.project_path).to eq("/path/to/project")
      expect(fact.valid_from).to eq("2024-01-01")
      expect(fact.valid_to).to eq("2024-12-31")
      expect(fact.created_at).to eq("2024-01-01")
    end

    it "freezes the object" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value")
      expect(fact).to be_frozen
    end

    it "raises error for missing predicate" do
      expect {
        described_class.new(id: 1, object_literal: "value")
      }.to raise_error(ArgumentError, "predicate required")
    end

    it "raises error for missing object_literal" do
      expect {
        described_class.new(id: 1, predicate: "test")
      }.to raise_error(ArgumentError, "object_literal required")
    end

    it "raises error for invalid confidence" do
      expect {
        described_class.new(id: 1, predicate: "test", object_literal: "value", confidence: 1.5)
      }.to raise_error(ArgumentError, "confidence must be between 0 and 1")
    end

    it "raises error for negative confidence" do
      expect {
        described_class.new(id: 1, predicate: "test", object_literal: "value", confidence: -0.1)
      }.to raise_error(ArgumentError, "confidence must be between 0 and 1")
    end
  end

  describe "#active?" do
    it "returns true for active status" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", status: "active")
      expect(fact.active?).to be true
    end

    it "returns false for non-active status" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", status: "superseded")
      expect(fact.active?).to be false
    end
  end

  describe "#superseded?" do
    it "returns true for superseded status" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", status: "superseded")
      expect(fact.superseded?).to be true
    end

    it "returns false for active status" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", status: "active")
      expect(fact.superseded?).to be false
    end
  end

  describe "#global?" do
    it "returns true for global scope" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", scope: "global")
      expect(fact.global?).to be true
    end

    it "returns false for project scope" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", scope: "project")
      expect(fact.global?).to be false
    end
  end

  describe "#project?" do
    it "returns true for project scope" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", scope: "project")
      expect(fact.project?).to be true
    end

    it "returns false for global scope" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value", scope: "global")
      expect(fact.project?).to be false
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      fact = described_class.new(
        id: 1,
        subject_name: "repo",
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        status: "active",
        confidence: 0.9,
        scope: "project",
        project_path: "/path",
        valid_from: "2024-01-01",
        valid_to: "2024-12-31",
        created_at: "2024-01-01"
      )

      hash = fact.to_h
      expect(hash).to eq({
        id: 1,
        subject_name: "repo",
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        status: "active",
        confidence: 0.9,
        scope: "project",
        project_path: "/path",
        valid_from: "2024-01-01",
        valid_to: "2024-12-31",
        created_at: "2024-01-01"
      })
    end

    it "includes nil values for missing optional attributes" do
      fact = described_class.new(id: 1, predicate: "test", object_literal: "value")
      hash = fact.to_h

      expect(hash[:subject_name]).to be_nil
      expect(hash[:project_path]).to be_nil
      expect(hash[:valid_from]).to be_nil
      expect(hash[:valid_to]).to be_nil
      expect(hash[:created_at]).to be_nil
    end
  end
end
