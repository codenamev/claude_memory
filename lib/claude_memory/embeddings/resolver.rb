# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Resolves an embedding provider by name, model, or ENV.
    #
    # Provider selection (in priority order):
    #   1. Explicit name parameter
    #   2. CLAUDE_MEMORY_EMBEDDING_PROVIDER env var
    #   3. Default: "tfidf"
    #
    # Model selection is forwarded to the provider via CLAUDE_MEMORY_EMBEDDING_MODEL
    # or the model parameter. The model can also imply the provider:
    #   - "BAAI/bge-small-en-v1.5" → fastembed
    #   - "text-embedding-3-small" → api
    #
    # Examples:
    #   Embeddings.resolve                                    # tfidf default
    #   Embeddings.resolve("fastembed")                       # fastembed with default model
    #   Embeddings.resolve("fastembed", model: "BAAI/bge-base-en-v1.5")
    #   Embeddings.resolve(model: "text-embedding-3-small")   # auto-detects api provider
    #
    def self.resolve(name = nil, model: nil, env: ENV)
      model ||= env["CLAUDE_MEMORY_EMBEDDING_MODEL"]
      provider = name || env["CLAUDE_MEMORY_EMBEDDING_PROVIDER"] || infer_provider(model) || "tfidf"

      case provider
      when "tfidf" then Generator.new
      when "fastembed" then FastembedAdapter.new(model_name: model, env: env)
      when "api" then ApiAdapter.new(model: model, env: env)
      else raise ArgumentError, "Unknown embedding provider: #{provider}. Available: tfidf, fastembed, api"
      end
    end

    # Infer provider from a model name using the registry.
    # Returns nil if the model is unknown.
    def self.infer_provider(model)
      return nil unless model

      ModelRegistry.find(model)&.provider
    end
    private_class_method :infer_provider
  end
end
