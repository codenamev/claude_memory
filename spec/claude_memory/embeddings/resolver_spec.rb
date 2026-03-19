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

      provider = described_class.resolve("fastembed")
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
  end
end
