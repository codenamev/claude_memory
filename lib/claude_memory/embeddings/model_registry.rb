# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Registry of known embedding models with their properties.
    # Enables model validation, dimension lookup, and discoverability.
    #
    # Models are registered by canonical name (e.g., "BAAI/bge-small-en-v1.5")
    # with provider type, dimensions, and description.
    #
    # Usage:
    #   ModelRegistry.find("BAAI/bge-small-en-v1.5")
    #   # => {provider: "fastembed", dimensions: 384, description: "...", ...}
    #
    #   ModelRegistry.models_for_provider("fastembed")
    #   # => [...]
    #
    class ModelRegistry
      ModelInfo = Data.define(:name, :provider, :dimensions, :description, :size_mb, :max_tokens)

      # Known models with validated dimensions.
      # Fastembed models sourced from fastembed-rb SUPPORTED_MODELS.
      # API models sourced from provider documentation.
      MODELS = [
        # --- fastembed: local ONNX models (no API key needed) ---
        ModelInfo.new(
          name: "BAAI/bge-small-en-v1.5",
          provider: "fastembed",
          dimensions: 384,
          description: "Fast English embedding (default)",
          size_mb: 67,
          max_tokens: 512
        ),
        ModelInfo.new(
          name: "BAAI/bge-base-en-v1.5",
          provider: "fastembed",
          dimensions: 768,
          description: "Balanced English embedding, higher accuracy",
          size_mb: 210,
          max_tokens: 512
        ),
        ModelInfo.new(
          name: "BAAI/bge-large-en-v1.5",
          provider: "fastembed",
          dimensions: 1024,
          description: "High accuracy English embedding",
          size_mb: 1200,
          max_tokens: 512
        ),
        ModelInfo.new(
          name: "sentence-transformers/all-MiniLM-L6-v2",
          provider: "fastembed",
          dimensions: 384,
          description: "Lightweight general-purpose sentence embedding",
          size_mb: 90,
          max_tokens: 512
        ),
        ModelInfo.new(
          name: "intfloat/multilingual-e5-small",
          provider: "fastembed",
          dimensions: 384,
          description: "Multilingual embedding, 100+ languages",
          size_mb: 450,
          max_tokens: 512
        ),
        ModelInfo.new(
          name: "intfloat/multilingual-e5-base",
          provider: "fastembed",
          dimensions: 768,
          description: "Larger multilingual embedding",
          size_mb: 1110,
          max_tokens: 512
        ),
        ModelInfo.new(
          name: "nomic-ai/nomic-embed-text-v1.5",
          provider: "fastembed",
          dimensions: 768,
          description: "Long context (8192 tokens) with Matryoshka support",
          size_mb: 520,
          max_tokens: 8192
        ),
        ModelInfo.new(
          name: "jinaai/jina-embeddings-v2-small-en",
          provider: "fastembed",
          dimensions: 512,
          description: "Small English embedding, 8192 token context",
          size_mb: 60,
          max_tokens: 8192
        ),
        ModelInfo.new(
          name: "jinaai/jina-embeddings-v2-base-en",
          provider: "fastembed",
          dimensions: 768,
          description: "Base English embedding, 8192 token context",
          size_mb: 520,
          max_tokens: 8192
        ),

        # --- api: OpenAI-compatible endpoints ---
        ModelInfo.new(
          name: "text-embedding-3-small",
          provider: "api",
          dimensions: 1536,
          description: "OpenAI small embedding (default API model)",
          size_mb: nil,
          max_tokens: 8191
        ),
        ModelInfo.new(
          name: "text-embedding-3-large",
          provider: "api",
          dimensions: 3072,
          description: "OpenAI large embedding, highest accuracy",
          size_mb: nil,
          max_tokens: 8191
        ),
        ModelInfo.new(
          name: "text-embedding-ada-002",
          provider: "api",
          dimensions: 1536,
          description: "OpenAI legacy embedding",
          size_mb: nil,
          max_tokens: 8191
        ),
        ModelInfo.new(
          name: "voyage-3",
          provider: "api",
          dimensions: 1024,
          description: "Voyage AI general-purpose embedding",
          size_mb: nil,
          max_tokens: 32000
        ),
        ModelInfo.new(
          name: "voyage-3-lite",
          provider: "api",
          dimensions: 512,
          description: "Voyage AI lightweight embedding",
          size_mb: nil,
          max_tokens: 32000
        ),
        ModelInfo.new(
          name: "voyage-code-3",
          provider: "api",
          dimensions: 1024,
          description: "Voyage AI code-optimized embedding",
          size_mb: nil,
          max_tokens: 32000
        ),

        # --- tfidf: built-in, no dependencies ---
        ModelInfo.new(
          name: "tfidf",
          provider: "tfidf",
          dimensions: 384,
          description: "Built-in TF-IDF embedding (no dependencies)",
          size_mb: 0,
          max_tokens: nil
        )
      ].freeze

      MODELS_BY_NAME = MODELS.each_with_object({}) { |m, h| h[m.name] = m }.freeze

      # Find a model by name.
      # @param name [String] model name (e.g., "BAAI/bge-small-en-v1.5")
      # @return [ModelInfo, nil]
      def self.find(name)
        MODELS_BY_NAME[name]
      end

      # List all models for a given provider.
      # @param provider [String] "fastembed", "api", or "tfidf"
      # @return [Array<ModelInfo>]
      def self.models_for_provider(provider)
        MODELS.select { |m| m.provider == provider }
      end

      # All known model names.
      # @return [Array<String>]
      def self.model_names
        MODELS.map(&:name)
      end

      # All provider names.
      # @return [Array<String>]
      def self.providers
        MODELS.map(&:provider).uniq
      end

      # Look up dimensions for a model name. Returns nil if unknown.
      # @param name [String] model name
      # @return [Integer, nil]
      def self.dimensions_for(name)
        find(name)&.dimensions
      end
    end
  end
end
