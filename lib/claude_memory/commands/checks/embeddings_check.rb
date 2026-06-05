# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Surfaces the active embedding provider, model, and dimension
      # alignment between provider and stored vectors.
      #
      # Doctor previously had VecCheck (sqlite-vec extension + index
      # coverage) but no signal about which provider was actually in use —
      # so a user could see "sqlite-vec available ✓" while silently
      # running on tfidf default when fastembed was loadable. This check
      # closes that visibility gap and points users at
      # `claude-memory setup-vectors` to opt into fastembed.
      class EmbeddingsCheck
        FASTEMBED_HINT = "Set CLAUDE_MEMORY_EMBEDDING_PROVIDER=fastembed for higher-quality semantic recall (fastembed is loadable on this system). " \
          "Run 'claude-memory setup-vectors' to configure."

        FASTEMBED_INSTALL_HINT = "fastembed is not installed; semantic recall is using tfidf (lower quality). " \
          "Run 'claude-memory setup-vectors' to install fastembed and switch."

        def call
          provider = Embeddings.resolve
          provider_name = provider.name
          warnings = []

          # Hint when user is on default tfidf — different message
          # depending on whether fastembed is even loadable.
          if provider_name == "tfidf"
            warnings << (fastembed_loadable? ? FASTEMBED_HINT : FASTEMBED_INSTALL_HINT)
          end

          dim_mismatches = check_dimension_alignment(provider)
          warnings.concat(dim_mismatches)

          {
            status: warnings.any? ? :warning : :ok,
            label: "embeddings",
            message: "Embedding provider: #{provider_name}, dimensions: #{provider.dimensions}",
            details: {
              provider: provider_name,
              dimensions: provider.dimensions,
              fastembed_loadable: fastembed_loadable?
            },
            warnings: warnings
          }
        rescue => e
          {
            status: :warning,
            label: "embeddings",
            message: "Embedding provider check failed: #{e.message}",
            details: {},
            warnings: []
          }
        end

        private

        def fastembed_loadable?
          return @fastembed_loadable if defined?(@fastembed_loadable)
          @fastembed_loadable = begin
            require "fastembed"
            true
          rescue LoadError
            false
          end
        end

        def check_dimension_alignment(provider)
          config = Configuration.new
          mismatches = []

          [config.global_db_path, config.project_db_path].each do |db_path|
            next unless File.exist?(db_path)

            store = nil
            begin
              store = Store::SQLiteStore.new(db_path)
              result = Embeddings::DimensionCheck.call(store, provider)
              next unless result.status == :mismatch

              mismatches << "Dimension mismatch in #{File.basename(File.dirname(db_path))} DB: " \
                "stored=#{result.stored} but current provider produces #{result.current}. " \
                "Run 'claude-memory index --force' to re-embed under the current provider."
            rescue => e
              ClaudeMemory.logger.debug("EmbeddingsCheck dimension check failed for #{db_path}: #{e.message}")
            ensure
              store&.close
            end
          end

          mismatches
        end
      end
    end
  end
end
