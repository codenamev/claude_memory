# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/shared_examples/embedding_provider"

RSpec.describe ClaudeMemory::Embeddings::FastembedAdapter do
  # Use real fastembed; skip if gem unavailable (e.g., model download fails in CI)
  def build_adapter(**kwargs)
    described_class.new(**kwargs)
  rescue LoadError, StandardError => e
    skip "fastembed not available: #{e.message}"
  end

  subject { build_adapter(env: {}) }

  it_behaves_like "an embedding provider"

  describe "#initialize" do
    it "uses default model when no config is given" do
      adapter = build_adapter(env: {})
      expect(adapter.model_name).to eq("BAAI/bge-small-en-v1.5")
      expect(adapter.dimensions).to eq(384)
    end

    it "reads model from CLAUDE_MEMORY_EMBEDDING_MODEL env" do
      # bge-base is a known registry model with different dimensions
      adapter = build_adapter(env: {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "BAAI/bge-base-en-v1.5"})
      expect(adapter.model_name).to eq("BAAI/bge-base-en-v1.5")
      expect(adapter.dimensions).to eq(768)
    end

    it "prefers explicit model_name over env" do
      adapter = build_adapter(
        model_name: "BAAI/bge-large-en-v1.5",
        env: {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "BAAI/bge-small-en-v1.5"}
      )
      expect(adapter.model_name).to eq("BAAI/bge-large-en-v1.5")
      expect(adapter.dimensions).to eq(1024)
    end

    it "raises LoadError when fastembed gem is missing" do
      allow_any_instance_of(described_class).to receive(:require).with("fastembed").and_raise(LoadError)

      expect {
        described_class.new(env: {})
      }.to raise_error(LoadError, /fastembed gem is required/)
    end
  end

  describe "#name" do
    it "returns 'fastembed'" do
      adapter = build_adapter(env: {})
      expect(adapter.name).to eq("fastembed")
    end
  end

  describe "#generate" do
    it "returns embedding vector with correct dimensions" do
      adapter = build_adapter(env: {})
      result = adapter.generate("What database does this project use?")
      expect(result).to be_an(Array)
      expect(result.size).to eq(384)
      expect(result).to all(be_a(Float))
    end

    it "returns zero vector for nil input" do
      adapter = build_adapter(env: {})
      result = adapter.generate(nil)
      expect(result).to eq(Array.new(adapter.dimensions, 0.0))
    end

    it "returns zero vector for empty input" do
      adapter = build_adapter(env: {})
      result = adapter.generate("")
      expect(result).to eq(Array.new(adapter.dimensions, 0.0))
    end
  end

  describe "#generate_passage" do
    it "returns passage embedding with correct dimensions" do
      adapter = build_adapter(env: {})
      result = adapter.generate_passage("This project uses PostgreSQL for the main database")
      expect(result).to be_an(Array)
      expect(result.size).to eq(384)
      expect(result).to all(be_a(Float))
    end
  end
end
