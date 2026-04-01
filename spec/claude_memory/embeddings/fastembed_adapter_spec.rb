# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Embeddings::FastembedAdapter do
  # Stub fastembed since it requires model downloads
  let(:fake_model_class) do
    Class.new do
      define_method(:initialize) { |**_| }
      define_method(:query_embed) { |_text| [Array.new(384, 0.1)] }
      define_method(:passage_embed) { |_text| [Array.new(384, 0.2)] }
    end
  end

  before do
    stub_const("Fastembed::TextEmbedding", fake_model_class)
    allow_any_instance_of(described_class).to receive(:require).with("fastembed")
  end

  describe "#initialize" do
    it "uses default model when no config is given" do
      adapter = described_class.new(env: {})
      expect(adapter.model_name).to eq("BAAI/bge-small-en-v1.5")
      expect(adapter.dimensions).to eq(384)
    end

    it "reads model from CLAUDE_MEMORY_EMBEDDING_MODEL env" do
      adapter = described_class.new(env: {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "BAAI/bge-base-en-v1.5"})
      expect(adapter.model_name).to eq("BAAI/bge-base-en-v1.5")
      expect(adapter.dimensions).to eq(768)
    end

    it "prefers explicit model_name over env" do
      adapter = described_class.new(
        model_name: "BAAI/bge-large-en-v1.5",
        env: {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "BAAI/bge-small-en-v1.5"}
      )
      expect(adapter.model_name).to eq("BAAI/bge-large-en-v1.5")
      expect(adapter.dimensions).to eq(1024)
    end

    it "probes dimensions for unknown models" do
      # Stub SUPPORTED_MODELS lookup to return nil (unknown model)
      stub_const("Fastembed::SUPPORTED_MODELS", [])

      adapter = described_class.new(model_name: "custom/unknown-model", env: {})
      # Falls through to probe: query_embed returns 384-dim from our fake
      expect(adapter.dimensions).to eq(384)
    end

    it "raises LoadError when fastembed gem is missing" do
      # Un-stub to test the real require path
      allow_any_instance_of(described_class).to receive(:require).with("fastembed").and_raise(LoadError)

      expect {
        described_class.new(env: {})
      }.to raise_error(LoadError, /fastembed gem is required/)
    end
  end

  describe "#name" do
    it "returns 'fastembed'" do
      adapter = described_class.new(env: {})
      expect(adapter.name).to eq("fastembed")
    end
  end

  describe "#generate" do
    it "returns embedding vector for text" do
      adapter = described_class.new(env: {})
      result = adapter.generate("test query")
      expect(result).to be_an(Array)
      expect(result.size).to eq(384)
    end

    it "returns zero vector for nil input" do
      adapter = described_class.new(env: {})
      result = adapter.generate(nil)
      expect(result).to eq(Array.new(384, 0.0))
    end

    it "returns zero vector for empty input" do
      adapter = described_class.new(env: {})
      result = adapter.generate("")
      expect(result).to eq(Array.new(384, 0.0))
    end
  end

  describe "#generate_passage" do
    it "returns passage embedding" do
      adapter = described_class.new(env: {})
      result = adapter.generate_passage("test passage")
      expect(result).to be_an(Array)
      expect(result.size).to eq(384)
    end
  end
end
