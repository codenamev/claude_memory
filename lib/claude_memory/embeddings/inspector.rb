# frozen_string_literal: true

module ClaudeMemory
  module Embeddings
    # Reads embedding metadata from global and project databases.
    # Returns structured data — no I/O formatting or stdout output.
    #
    # Used by EmbeddingsCommand to separate DB concerns from presentation.
    class Inspector
      DatabaseState = Data.define(:label, :provider, :dimensions)
      DimensionResult = Data.define(:label, :status, :stored_dims, :stored_provider, :current_dims)

      def database_states
        results = []

        with_each_store do |label, store|
          provider = store.get_meta("embedding_provider")
          dims = store.get_meta("embedding_dimensions")

          next unless provider || dims

          results << DatabaseState.new(label: label, provider: provider, dimensions: dims)
        end

        results
      end

      def dimension_checks(provider_name, model_name)
        results = []

        with_each_store do |label, store|
          stored_dims = store.get_meta("embedding_dimensions")&.to_i
          stored_provider = store.get_meta("embedding_provider")

          if stored_dims
            current_dims = resolve_current_dimensions(provider_name, model_name)

            status = if current_dims && current_dims != stored_dims
              :mismatch
            else
              :match
            end

            results << DimensionResult.new(
              label: label,
              status: status,
              stored_dims: stored_dims,
              stored_provider: stored_provider,
              current_dims: current_dims
            )
          else
            results << DimensionResult.new(
              label: label,
              status: :fresh,
              stored_dims: nil,
              stored_provider: nil,
              current_dims: nil
            )
          end
        end

        results
      end

      private

      def resolve_current_dimensions(provider_name, model_name)
        if model_name
          ModelRegistry.dimensions_for(model_name)
        else
          ModelRegistry.default_for_provider(provider_name)&.dimensions
        end
      end

      def with_each_store
        config = Configuration.new

        [["global", config.global_db_path], ["project", config.project_db_path]].each do |label, path|
          next unless File.exist?(path)

          store = Store::SQLiteStore.new(path)
          begin
            yield label, store
          ensure
            store.close
          end
        end
      end
    end
  end
end
