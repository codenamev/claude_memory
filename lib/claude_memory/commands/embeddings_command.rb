# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Shows embedding configuration, lists available models, and validates setup.
    #
    # Subcommands:
    #   claude-memory embeddings          # Show current config
    #   claude-memory embeddings list     # List available models
    #   claude-memory embeddings check    # Validate current setup
    #
    class EmbeddingsCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory embeddings [list|check]"
          end
        end
        return 1 if opts.nil?

        subcommand = args.first

        case subcommand
        when "list" then list_models
        when "check" then check_setup
        when nil then show_config
        else
          failure("Unknown subcommand: #{subcommand}. Use: list, check")
        end
      end

      private

      def show_config
        provider = ENV["CLAUDE_MEMORY_EMBEDDING_PROVIDER"] || "tfidf"
        model = ENV["CLAUDE_MEMORY_EMBEDDING_MODEL"]
        api_url = ENV["CLAUDE_MEMORY_EMBEDDING_API_URL"]

        stdout.puts "Embedding Configuration"
        stdout.puts "======================"
        stdout.puts "Provider:  #{provider}"
        stdout.puts "Model:     #{model || "(default)"}"

        # Show resolved model info
        if model
          info = Embeddings::ModelRegistry.find(model)
          if info
            stdout.puts "Dimensions: #{info.dimensions}"
            stdout.puts "Description: #{info.description}"
          else
            stdout.puts "Dimensions: (unknown - will be discovered at runtime)"
          end
        else
          info = Embeddings::ModelRegistry.default_for_provider(provider)
          if info
            stdout.puts "Default model: #{info.name}"
            stdout.puts "Dimensions: #{info.dimensions}"
          end
        end

        stdout.puts "API URL:   #{api_url}" if api_url && provider == "api"

        # Show database state if available
        show_database_state

        stdout.puts ""
        stdout.puts "ENV variables:"
        stdout.puts "  CLAUDE_MEMORY_EMBEDDING_PROVIDER  Provider (tfidf, fastembed, api)"
        stdout.puts "  CLAUDE_MEMORY_EMBEDDING_MODEL     Model name"
        stdout.puts "  CLAUDE_MEMORY_EMBEDDING_API_KEY   API key (for api provider)"
        stdout.puts "  CLAUDE_MEMORY_EMBEDDING_API_URL   API endpoint (for api provider)"
        0
      end

      def list_models
        Embeddings::ModelRegistry.providers.each do |provider|
          stdout.puts ""
          stdout.puts "#{provider_label(provider)}:"
          stdout.puts "-" * 40

          Embeddings::ModelRegistry.models_for_provider(provider).each do |model|
            size = model.size_mb ? "#{model.size_mb}MB" : "cloud"
            tokens = model.max_tokens ? "#{model.max_tokens} tokens" : ""
            stdout.puts "  #{model.name}"
            stdout.puts "    #{model.dimensions}-dim | #{size} | #{tokens}"
            stdout.puts "    #{model.description}"
          end
        end

        stdout.puts ""
        stdout.puts "Custom models: Set CLAUDE_MEMORY_EMBEDDING_MODEL to any model"
        stdout.puts "supported by your provider. Dimensions are auto-detected."
        0
      end

      def check_setup
        provider_name = ENV["CLAUDE_MEMORY_EMBEDDING_PROVIDER"] || "tfidf"
        model_name = ENV["CLAUDE_MEMORY_EMBEDDING_MODEL"]

        stdout.puts "Checking embedding setup..."
        stdout.puts ""

        ok = true

        # Check provider availability
        case provider_name
        when "fastembed"
          ok &= check_fastembed
        when "api"
          ok &= check_api_config
        when "tfidf"
          stdout.puts "  [OK] tfidf provider (built-in, always available)"
        else
          stdout.puts "  [FAIL] Unknown provider: #{provider_name}"
          ok = false
        end

        # Check model validity
        if model_name
          info = Embeddings::ModelRegistry.find(model_name)
          if info
            if info.provider != provider_name
              stdout.puts "  [WARN] Model '#{model_name}' is for '#{info.provider}' provider, but '#{provider_name}' is selected"
              stdout.puts "         Set CLAUDE_MEMORY_EMBEDDING_PROVIDER=#{info.provider}"
            else
              stdout.puts "  [OK] Model '#{model_name}' (#{info.dimensions}-dim)"
            end
          else
            stdout.puts "  [INFO] Model '#{model_name}' not in registry (dimensions will be auto-detected)"
          end
        end

        # Check database dimension compatibility
        ok &= check_dimension_compatibility(provider_name, model_name)

        stdout.puts ""
        stdout.puts ok ? "All checks passed." : "Some checks failed. See above."
        ok ? 0 : 1
      end

      def check_fastembed
        require "fastembed"
        stdout.puts "  [OK] fastembed gem available"
        true
      rescue LoadError
        stdout.puts "  [FAIL] fastembed gem not installed"
        stdout.puts "         Add `gem 'fastembed'` to your Gemfile"
        false
      end

      def check_api_config
        key = ENV["CLAUDE_MEMORY_EMBEDDING_API_KEY"] || ENV["OPENAI_API_KEY"]
        if key
          stdout.puts "  [OK] API key configured"
          true
        else
          stdout.puts "  [FAIL] No API key found"
          stdout.puts "         Set CLAUDE_MEMORY_EMBEDDING_API_KEY or OPENAI_API_KEY"
          false
        end
      end

      def check_dimension_compatibility(provider_name, model_name)
        ok = true

        with_each_store do |label, store|
          stored_dims = store.get_meta("embedding_dimensions")&.to_i
          stored_provider = store.get_meta("embedding_provider")

          if stored_dims
            current_dims = resolve_current_dimensions(provider_name, model_name)

            if current_dims && current_dims != stored_dims
              stdout.puts "  [WARN] #{label}: Dimension mismatch (stored: #{stored_dims}, current: #{current_dims})"
              stdout.puts "         Re-index with: claude-memory index --force --scope #{label}"
              ok = false
            else
              stdout.puts "  [OK] #{label}: #{stored_dims}-dim (provider: #{stored_provider || "unknown"})"
            end
          else
            stdout.puts "  [INFO] #{label}: No embeddings indexed yet"
          end
        end

        ok
      end

      def resolve_current_dimensions(provider_name, model_name)
        if model_name
          Embeddings::ModelRegistry.dimensions_for(model_name)
        else
          Embeddings::ModelRegistry.default_for_provider(provider_name)&.dimensions
        end
      end

      def provider_label(provider)
        case provider
        when "fastembed" then "fastembed (local ONNX, no API key)"
        when "api" then "api (OpenAI-compatible endpoints, requires API key)"
        when "tfidf" then "tfidf (built-in, no dependencies)"
        end
      end

      def show_database_state
        with_each_store do |label, store|
          stored_provider = store.get_meta("embedding_provider")
          stored_dims = store.get_meta("embedding_dimensions")

          next unless stored_provider || stored_dims

          stdout.puts ""
          stdout.puts "#{label.capitalize} DB: provider=#{stored_provider || "unknown"}, dimensions=#{stored_dims || "unknown"}"
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
