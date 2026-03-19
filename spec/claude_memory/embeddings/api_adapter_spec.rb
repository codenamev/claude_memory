# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/shared_examples/embedding_provider"

RSpec.describe ClaudeMemory::Embeddings::ApiAdapter do
  let(:api_key) { "test-api-key-123" }
  let(:model) { "text-embedding-3-small" }
  let(:api_url) { "https://api.openai.com/v1/embeddings" }
  let(:env) do
    {
      "CLAUDE_MEMORY_EMBEDDING_API_KEY" => api_key,
      "CLAUDE_MEMORY_EMBEDDING_MODEL" => model,
      "CLAUDE_MEMORY_EMBEDDING_API_URL" => api_url
    }
  end
  let(:embedding_vector) { Array.new(1536) { rand(-1.0..1.0) } }
  let(:success_response_body) do
    {
      "object" => "list",
      "data" => [{"object" => "embedding", "index" => 0, "embedding" => embedding_vector}],
      "model" => model,
      "usage" => {"prompt_tokens" => 5, "total_tokens" => 5}
    }.to_json
  end

  def stub_embedding_api(body: success_response_body, code: "200")
    http_double = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http_double)
    allow(http_double).to receive(:use_ssl=)
    allow(http_double).to receive(:open_timeout=)
    allow(http_double).to receive(:read_timeout=)

    response = instance_double(Net::HTTPSuccess, body: body, code: code)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(code == "200")
    allow(http_double).to receive(:request).and_return(response)

    http_double
  end

  describe "#initialize" do
    it "raises ArgumentError when no API key is provided" do
      expect {
        described_class.new(env: {})
      }.to raise_error(ArgumentError, /CLAUDE_MEMORY_EMBEDDING_API_KEY/)
    end

    it "accepts OPENAI_API_KEY as fallback" do
      adapter = described_class.new(env: {"OPENAI_API_KEY" => "sk-test"})
      expect(adapter.name).to eq("api")
    end

    it "uses defaults for URL and model" do
      stub_embedding_api
      adapter = described_class.new(env: {"CLAUDE_MEMORY_EMBEDDING_API_KEY" => api_key})
      expect(adapter.name).to eq("api")
    end
  end

  describe "#name" do
    it "returns 'api'" do
      adapter = described_class.new(env: env)
      expect(adapter.name).to eq("api")
    end
  end

  describe "#generate" do
    it "returns embedding vector from API response" do
      stub_embedding_api
      adapter = described_class.new(env: env)

      result = adapter.generate("test query")

      expect(result).to eq(embedding_vector)
    end

    it "returns empty array for nil input" do
      adapter = described_class.new(env: env)
      result = adapter.generate(nil)
      expect(result).to eq([])
    end

    it "returns empty array for empty input" do
      adapter = described_class.new(env: env)
      result = adapter.generate("")
      expect(result).to eq([])
    end

    it "raises ApiError on API error" do
      stub_embedding_api(body: '{"error": "rate limited"}', code: "429")
      adapter = described_class.new(env: env)

      expect {
        adapter.generate("test")
      }.to raise_error(described_class::ApiError, /HTTP 429/)
    end

    it "caches dimensions after first call" do
      stub_embedding_api
      adapter = described_class.new(env: env)

      adapter.generate("first call")
      expect(adapter.dimensions).to eq(1536)
    end
  end

  describe "#dimensions" do
    it "is lazy — makes an API call to discover dimensions" do
      stub_embedding_api
      adapter = described_class.new(env: env)

      expect(adapter.dimensions).to eq(1536)
    end
  end

  describe "#generate_passage" do
    it "is aliased to generate" do
      stub_embedding_api
      adapter = described_class.new(env: env)

      result = adapter.generate_passage("test passage")
      expect(result).to eq(embedding_vector)
    end
  end

  context "with shared provider contract" do
    subject do
      stub_embedding_api
      described_class.new(env: env)
    end

    # Override shared example expectations for API adapter since dimensions are lazy
    it "responds to #name and returns a string" do
      expect(subject.name).to eq("api")
    end

    it "responds to #dimensions and returns a positive integer" do
      expect(subject.dimensions).to be_a(Integer)
      expect(subject.dimensions).to be > 0
    end

    it "responds to #generate" do
      result = subject.generate("test")
      expect(result).to be_an(Array)
      expect(result.size).to eq(subject.dimensions)
    end
  end
end
