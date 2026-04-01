# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Embeddings do
  describe ".resolve" do
    it "defaults to tfidf when no name or ENV is set" do
      provider = described_class.resolve(env: {})
      expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
      expect(provider.name).to eq("tfidf")
    end

    it "resolves 'tfidf' by name" do
      provider = described_class.resolve("tfidf")
      expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
    end

    it "resolves 'fastembed' by name" do
      # fastembed gem may not be installed; stub the require
      stub_const("Fastembed::TextEmbedding", Class.new { define_method(:initialize) { |**_| } })
      allow_any_instance_of(ClaudeMemory::Embeddings::FastembedAdapter).to receive(:require).with("fastembed")

      provider = described_class.resolve("fastembed", env: {})
      expect(provider).to be_a(ClaudeMemory::Embeddings::FastembedAdapter)
      expect(provider.name).to eq("fastembed")
    end

    it "resolves 'api' by name with API key" do
      provider = described_class.resolve("api", env: {"CLAUDE_MEMORY_EMBEDDING_API_KEY" => "test-key"})
      expect(provider).to be_a(ClaudeMemory::Embeddings::ApiAdapter)
      expect(provider.name).to eq("api")
    end

    it "raises for 'api' without API key" do
      expect {
        described_class.resolve("api", env: {})
      }.to raise_error(ArgumentError, /CLAUDE_MEMORY_EMBEDDING_API_KEY/)
    end

    it "reads provider from CLAUDE_MEMORY_EMBEDDING_PROVIDER ENV" do
      provider = described_class.resolve(env: {"CLAUDE_MEMORY_EMBEDDING_PROVIDER" => "tfidf"})
      expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
    end

    it "explicit name overrides ENV" do
      provider = described_class.resolve("tfidf", env: {"CLAUDE_MEMORY_EMBEDDING_PROVIDER" => "api", "CLAUDE_MEMORY_EMBEDDING_API_KEY" => "k"})
      expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
    end

    it "raises ArgumentError for unknown provider" do
      expect {
        described_class.resolve("unknown")
      }.to raise_error(ArgumentError, /Unknown embedding provider: unknown/)
    end

    context "with model: parameter" do
      it "forwards model to fastembed adapter" do
        stub_const("Fastembed::TextEmbedding", Class.new { define_method(:initialize) { |**_| } })
        allow_any_instance_of(ClaudeMemory::Embeddings::FastembedAdapter).to receive(:require).with("fastembed")

        provider = described_class.resolve("fastembed", model: "BAAI/bge-base-en-v1.5", env: {})
        expect(provider.model_name).to eq("BAAI/bge-base-en-v1.5")
        expect(provider.dimensions).to eq(768)
      end

      it "forwards model to api adapter" do
        provider = described_class.resolve("api", model: "text-embedding-3-large", env: {"CLAUDE_MEMORY_EMBEDDING_API_KEY" => "k"})
        expect(provider.dimensions).to eq(3072)
      end

      it "infers provider from model name when no provider given" do
        stub_const("Fastembed::TextEmbedding", Class.new { define_method(:initialize) { |**_| } })
        allow_any_instance_of(ClaudeMemory::Embeddings::FastembedAdapter).to receive(:require).with("fastembed")

        provider = described_class.resolve(model: "BAAI/bge-small-en-v1.5", env: {})
        expect(provider).to be_a(ClaudeMemory::Embeddings::FastembedAdapter)
      end

      it "infers api provider from api model name" do
        provider = described_class.resolve(model: "text-embedding-3-small", env: {"CLAUDE_MEMORY_EMBEDDING_API_KEY" => "k"})
        expect(provider).to be_a(ClaudeMemory::Embeddings::ApiAdapter)
      end

      it "reads model from CLAUDE_MEMORY_EMBEDDING_MODEL ENV" do
        stub_const("Fastembed::TextEmbedding", Class.new { define_method(:initialize) { |**_| } })
        allow_any_instance_of(ClaudeMemory::Embeddings::FastembedAdapter).to receive(:require).with("fastembed")

        provider = described_class.resolve(env: {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "BAAI/bge-base-en-v1.5"})
        expect(provider).to be_a(ClaudeMemory::Embeddings::FastembedAdapter)
        expect(provider.dimensions).to eq(768)
      end

      it "falls back to tfidf when model is unknown and no provider set" do
        provider = described_class.resolve(model: "totally-unknown-model", env: {})
        expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
      end
    end
  end
end
