# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ClaudeMemory
  module Embeddings
    # Adapter for any OpenAI-compatible /v1/embeddings endpoint.
    # Works with OpenAI, Voyage, Ollama, LiteLLM, etc.
    #
    # Required ENV:
    #   CLAUDE_MEMORY_EMBEDDING_API_KEY or OPENAI_API_KEY
    #
    # Optional ENV:
    #   CLAUDE_MEMORY_EMBEDDING_API_URL (default: https://api.openai.com/v1/embeddings)
    #   CLAUDE_MEMORY_EMBEDDING_MODEL   (default: text-embedding-3-small)
    #
    class ApiAdapter
      class ApiError < StandardError; end

      DEFAULT_API_URL = "https://api.openai.com/v1/embeddings"
      DEFAULT_MODEL = "text-embedding-3-small"

      def initialize(env: ENV)
        @api_key = env["CLAUDE_MEMORY_EMBEDDING_API_KEY"] || env["OPENAI_API_KEY"]
        @api_url = env["CLAUDE_MEMORY_EMBEDDING_API_URL"] || DEFAULT_API_URL
        @model = env["CLAUDE_MEMORY_EMBEDDING_MODEL"] || DEFAULT_MODEL

        raise ArgumentError, "Set CLAUDE_MEMORY_EMBEDDING_API_KEY or OPENAI_API_KEY" unless @api_key
      end

      def name = "api"

      # Dimensions are lazy — derived from the first API response and cached.
      def dimensions
        @dimensions ||= fetch_dimensions
      end

      # Generate embedding for a query text.
      # @param text [String] input text to embed
      # @return [Array<Float>] embedding vector
      def generate(text)
        return zero_vector if text.nil? || text.empty?

        response = call_api(text)
        embedding = response.dig("data", 0, "embedding")

        raise ApiError, "No embedding returned in API response" unless embedding

        @dimensions ||= embedding.size
        embedding
      end

      # Alias for passage encoding — API providers don't distinguish query vs passage
      alias_method :generate_passage, :generate

      private

      def fetch_dimensions
        # Make a minimal API call to discover dimensions
        embedding = generate("dimension probe")
        embedding.size
      end

      def call_api(text)
        uri = URI(@api_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri.path)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate({input: text, model: @model})

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise ApiError, "HTTP #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def zero_vector
        # If dimensions haven't been discovered yet, we can't return a properly-sized zero vector.
        # Return empty array; callers handle nil/empty gracefully.
        return [] unless @dimensions

        Array.new(@dimensions, 0.0)
      end
    end
  end
end
