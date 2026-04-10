# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Embeddings::ModelRegistry do
  describe ".find" do
    it "returns ModelInfo for a known fastembed model" do
      info = described_class.find("BAAI/bge-small-en-v1.5")
      expect(info).not_to be_nil
      expect(info.provider).to eq("fastembed")
      expect(info.dimensions).to eq(384)
    end

    it "returns ModelInfo for a known API model" do
      info = described_class.find("text-embedding-3-small")
      expect(info).not_to be_nil
      expect(info.provider).to eq("api")
      expect(info.dimensions).to eq(1536)
    end

    it "returns ModelInfo for tfidf" do
      info = described_class.find("tfidf")
      expect(info).not_to be_nil
      expect(info.provider).to eq("tfidf")
      expect(info.dimensions).to eq(384)
    end

    it "returns nil for unknown models" do
      expect(described_class.find("unknown-model")).to be_nil
    end
  end

  describe ".models_for_provider" do
    it "returns all fastembed models" do
      models = described_class.models_for_provider("fastembed")
      expect(models).not_to be_empty
      expect(models).to all(have_attributes(provider: "fastembed"))
    end

    it "returns all API models" do
      models = described_class.models_for_provider("api")
      expect(models).not_to be_empty
      expect(models).to all(have_attributes(provider: "api"))
    end

    it "returns empty array for unknown provider" do
      expect(described_class.models_for_provider("unknown")).to eq([])
    end
  end

  describe ".dimensions_for" do
    it "returns dimensions for known models" do
      expect(described_class.dimensions_for("BAAI/bge-base-en-v1.5")).to eq(768)
      expect(described_class.dimensions_for("text-embedding-3-large")).to eq(3072)
    end

    it "returns nil for unknown models" do
      expect(described_class.dimensions_for("custom-model")).to be_nil
    end
  end

  describe ".providers" do
    it "returns all provider names" do
      providers = described_class.providers
      expect(providers).to include("fastembed", "api", "tfidf")
    end
  end

  describe ".model_names" do
    it "returns all model names" do
      names = described_class.model_names
      expect(names).to include("BAAI/bge-small-en-v1.5", "text-embedding-3-small", "tfidf")
    end
  end

  describe ".default_for_provider" do
    it "returns the default fastembed model" do
      info = described_class.default_for_provider("fastembed")
      expect(info).not_to be_nil
      expect(info.name).to eq("BAAI/bge-small-en-v1.5")
    end

    it "returns the default api model" do
      info = described_class.default_for_provider("api")
      expect(info).not_to be_nil
      expect(info.name).to eq("text-embedding-3-small")
    end

    it "returns the default tfidf model" do
      info = described_class.default_for_provider("tfidf")
      expect(info).not_to be_nil
      expect(info.name).to eq("tfidf")
    end

    it "returns nil for unknown provider" do
      expect(described_class.default_for_provider("unknown")).to be_nil
    end
  end

  describe "MODELS" do
    it "all have required fields" do
      described_class::MODELS.each do |model|
        expect(model.name).to be_a(String)
        expect(model.provider).to be_a(String)
        expect(model.dimensions).to be_a(Integer)
        expect(model.dimensions).to be > 0
        expect(model.description).to be_a(String)
      end
    end

    it "has unique model names" do
      names = described_class::MODELS.map(&:name)
      expect(names.uniq.size).to eq(names.size)
    end
  end
end
