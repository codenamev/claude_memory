# frozen_string_literal: true

require "digest"

module ClaudeMemory
  module Store
    # LLM cache persistence for the SQLiteStore.
    # Keyed on SHA-256 of "{operation}:{model}:{input_hash}" so identical
    # (operation, model, input) tuples collapse to a single row via upsert.
    # Pruning is age-based — callers decide the retention window.
    module LLMCache
      # Look up a cached LLM result by its cache key.
      # @param cache_key [String] SHA-256 hex cache key
      # @return [Hash, nil]
      def llm_cache_lookup(cache_key)
        llm_cache.where(cache_key: cache_key).first
      end

      # Store or update a cached LLM result. Uses upsert on the cache_key.
      # @param operation [String] operation name (e.g. "distill", "embed")
      # @param model [String] model identifier
      # @param input_hash [String] SHA-256 hex digest of the input
      # @param result_json [String] JSON-serialized result
      # @param input_tokens [Integer, nil] input tokens consumed
      # @param output_tokens [Integer, nil] output tokens consumed
      # @return [void]
      def llm_cache_store(operation:, model:, input_hash:, result_json:, input_tokens: nil, output_tokens: nil)
        cache_key = Digest::SHA256.hexdigest("#{operation}:#{model}:#{input_hash}")

        llm_cache
          .insert_conflict(target: :cache_key, update: {
            result_json: result_json,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            created_at: Time.now.utc.iso8601
          })
          .insert(
            cache_key: cache_key,
            operation: operation,
            model: model,
            input_hash: input_hash,
            result_json: result_json,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            created_at: Time.now.utc.iso8601
          )
      end

      # Compute the cache key for an LLM operation.
      # @param operation [String] operation name
      # @param model [String] model identifier
      # @param input [String] raw input text
      # @return [String] SHA-256 hex cache key
      def llm_cache_key(operation, model, input)
        input_hash = Digest::SHA256.hexdigest(input)
        Digest::SHA256.hexdigest("#{operation}:#{model}:#{input_hash}")
      end

      # Delete LLM cache entries older than the given age.
      # @param max_age_seconds [Integer] maximum age in seconds (default: 7 days)
      # @return [Integer] number of rows deleted
      def llm_cache_prune(max_age_seconds: 604_800)
        cutoff = (Time.now - max_age_seconds).utc.iso8601
        llm_cache.where { created_at < cutoff }.delete
      end
    end
  end
end
