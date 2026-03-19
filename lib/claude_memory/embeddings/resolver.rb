# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Resolves an embedding provider by name or ENV.
    # Three providers: tfidf (default), fastembed, api.
    def self.resolve(name = nil, env: ENV)
      provider = name || env["CLAUDE_MEMORY_EMBEDDING_PROVIDER"] || "tfidf"

      case provider
      when "tfidf" then Generator.new
      when "fastembed" then FastembedAdapter.new
      when "api" then ApiAdapter.new(env: env)
      else raise ArgumentError, "Unknown embedding provider: #{provider}. Available: tfidf, fastembed, api"
      end
    end
  end
end
