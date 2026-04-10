# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Adapter wrapping fastembed-rb for high-quality local embeddings.
    # Supports any model available in fastembed-rb's SUPPORTED_MODELS.
    #
    # Model selection (in priority order):
    #   1. Explicit model_name parameter
    #   2. CLAUDE_MEMORY_EMBEDDING_MODEL env var
    #   3. Default: BAAI/bge-small-en-v1.5 (384-dim, ~67MB ONNX)
    #
    # Dimensions are resolved from the ModelRegistry for known models,
    # or probed from fastembed's ModelInfo for unknown models.
    #
    # Usage:
    #   adapter = FastembedAdapter.new
    #   query_vec = adapter.generate("What database?")         # query encoding
    #   passage_vec = adapter.generate_passage("Uses PostgreSQL") # passage encoding
    #
    #   # Use a larger model:
    #   adapter = FastembedAdapter.new(model_name: "BAAI/bge-base-en-v1.5")
    #   adapter.dimensions  # => 768
    #
    class FastembedAdapter
      DEFAULT_MODEL = "BAAI/bge-small-en-v1.5"

      attr_reader :model_name, :dimensions

      def name = "fastembed"

      def initialize(model_name: nil, env: ENV)
        @model_name = model_name || env["CLAUDE_MEMORY_EMBEDDING_MODEL"] || DEFAULT_MODEL
        @dimensions = resolve_dimensions(@model_name)

        require "fastembed"
        @model = Fastembed::TextEmbedding.new(model_name: @model_name)

        # If dimensions weren't known from registry, probe from fastembed
        @dimensions ||= probe_dimensions_from_fastembed
      rescue LoadError
        raise LoadError,
          "fastembed gem is required for FastembedAdapter. Add `gem 'fastembed'` to your Gemfile."
      end

      # Generate query embedding (optimized for search queries)
      # @param text [String] query text to embed
      # @return [Array<Float>] normalized embedding vector
      def generate(text)
        return zero_vector if text.nil? || text.empty?

        @model.query_embed(text).first.to_a
      end

      # Generate passage embedding (optimized for document/fact indexing)
      # @param text [String] passage text to embed
      # @return [Array<Float>] normalized embedding vector
      def generate_passage(text)
        return zero_vector if text.nil? || text.empty?

        @model.passage_embed(text).first.to_a
      end

      private

      # Resolve dimensions from the model registry (fast, no I/O).
      # Returns nil if the model isn't in the registry.
      def resolve_dimensions(model)
        ModelRegistry.dimensions_for(model)
      end

      # Fallback: probe fastembed's SUPPORTED_MODELS for dimension info.
      # This handles models added to fastembed-rb but not yet in our registry.
      def probe_dimensions_from_fastembed
        if defined?(Fastembed::SUPPORTED_MODELS)
          info = Fastembed::SUPPORTED_MODELS[@model_name]
          return info.dim if info
        end

        # Last resort: generate a test embedding and measure its size
        @model.query_embed("dimension probe").first.size
      end

      def zero_vector
        Array.new(@dimensions, 0.0)
      end
    end
  end
end
