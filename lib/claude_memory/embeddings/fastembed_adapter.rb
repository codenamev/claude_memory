# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Adapter wrapping fastembed-rb for high-quality local embeddings
    # Uses BAAI/bge-small-en-v1.5 by default (384-dim, ~67MB ONNX model)
    #
    # Implements the same generate(text) interface as Generator for DI compatibility.
    # Supports asymmetric query/passage encoding for better retrieval accuracy.
    #
    # Usage:
    #   adapter = FastembedAdapter.new
    #   query_vec = adapter.generate("What database?")         # query encoding
    #   passage_vec = adapter.generate_passage("Uses PostgreSQL") # passage encoding
    #
    class FastembedAdapter
      EMBEDDING_DIM = 384
      DEFAULT_MODEL = "BAAI/bge-small-en-v1.5"

      def initialize(model_name: DEFAULT_MODEL)
        require "fastembed"
        @model = Fastembed::TextEmbedding.new(model_name: model_name)
      rescue LoadError
        raise LoadError,
          "fastembed gem is required for FastembedAdapter. Add `gem 'fastembed'` to your Gemfile."
      end

      # Generate query embedding (optimized for search queries)
      # Compatible with Recall's embedding_generator interface
      # @param text [String] query text to embed
      # @return [Array<Float>] normalized 384-dimensional vector
      def generate(text)
        return zero_vector if text.nil? || text.empty?

        @model.query_embed(text).first.to_a
      end

      # Generate passage embedding (optimized for document/fact indexing)
      # Use this when storing embeddings for facts
      # @param text [String] passage text to embed
      # @return [Array<Float>] normalized 384-dimensional vector
      def generate_passage(text)
        return zero_vector if text.nil? || text.empty?

        @model.passage_embed(text).first.to_a
      end

      private

      def zero_vector
        Array.new(EMBEDDING_DIM, 0.0)
      end
    end
  end
end
