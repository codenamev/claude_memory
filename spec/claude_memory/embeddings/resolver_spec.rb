# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Embeddings do
  describe ".resolve" do
    # Helper to resolve fastembed providers, skipping when gem unavailable
    def resolve_or_skip(...)
      described_class.resolve(...)
    rescue LoadError, StandardError => e
      skip "fastembed not available: #{e.message}"
    end

    it "defaults to tfidf when no name or ENV is set" do
      provider = described_class.resolve(env: {})
      expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
      expect(provider.name).to eq("tfidf")
      expect(provider.dimensions).to eq(384)
    end

    it "resolves 'tfidf' by name" do
      provider = described_class.resolve("tfidf")
      expect(provider).to be_a(ClaudeMemory::Embeddings::Generator)
    end

    it "resolves 'fastembed' by name" do
      provider = resolve_or_skip("fastembed", env: {})
      expect(provider).to be_a(ClaudeMemory::Embeddings::FastembedAdapter)
      expect(provider.name).to eq("fastembed")
      expect(provider.dimensions).to eq(384)
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
      it "forwards model to fastembed adapter with correct dimensions" do
        adapter = resolve_or_skip("fastembed", model: "BAAI/bge-base-en-v1.5", env: {})
        expect(adapter.model_name).to eq("BAAI/bge-base-en-v1.5")
        expect(adapter.dimensions).to eq(768)
      end

      it "forwards model to api adapter with registry dimensions" do
        provider = described_class.resolve("api", model: "text-embedding-3-large", env: {"CLAUDE_MEMORY_EMBEDDING_API_KEY" => "k"})
        expect(provider.dimensions).to eq(3072)
      end

      it "infers fastembed provider from model name" do
        provider = resolve_or_skip(model: "BAAI/bge-small-en-v1.5", env: {})
        expect(provider).to be_a(ClaudeMemory::Embeddings::FastembedAdapter)
      end

      it "infers api provider from api model name" do
        provider = described_class.resolve(model: "text-embedding-3-small", env: {"CLAUDE_MEMORY_EMBEDDING_API_KEY" => "k"})
        expect(provider).to be_a(ClaudeMemory::Embeddings::ApiAdapter)
      end

      it "reads model from CLAUDE_MEMORY_EMBEDDING_MODEL ENV and infers provider" do
        provider = resolve_or_skip(env: {"CLAUDE_MEMORY_EMBEDDING_MODEL" => "BAAI/bge-base-en-v1.5"})
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
