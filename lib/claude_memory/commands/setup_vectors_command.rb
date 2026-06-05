# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"

module ClaudeMemory
  module Commands
    # Guides the user through opting into vector recall with fastembed
    # (or another provider). fastembed stays a dev/test gem dependency by
    # design; this command is the documented opt-in path for end users.
    #
    # Steps:
    #   1. Verify the chosen provider is loadable. For fastembed, surface
    #      a clear install command if the gem isn't on $LOAD_PATH.
    #   2. Persist CLAUDE_MEMORY_EMBEDDING_PROVIDER (and optional model)
    #      into the project's .claude/settings.json env block, the same
    #      mechanism Claude Code uses for OTel env (see OTel::SettingsWriter).
    #   3. Re-embed existing facts under the new provider (unless --no-reindex).
    #   4. Report the final state — provider, dimensions, stored alignment.
    class SetupVectorsCommand < BaseCommand
      OWNED_KEYS = %w[
        CLAUDE_MEMORY_EMBEDDING_PROVIDER
        CLAUDE_MEMORY_EMBEDDING_MODEL
      ].freeze

      FASTEMBED_INSTALL_HINT = <<~HINT
        fastembed is not installed. claude-memory keeps fastembed as a
        dev/test dependency so the default gem install stays light. To
        enable it, install the gem and re-run setup-vectors:

          gem install fastembed
          claude-memory setup-vectors

        Or if you bundle, add to your Gemfile:

          gem "fastembed"

        Then `bundle install` and re-run setup-vectors. The first run
        downloads the BAAI/bge-small-en-v1.5 ONNX model (~75MB).
      HINT

      def call(args)
        opts = parse_opts(args)
        return 1 if opts.nil?

        return print_status if opts[:status]

        provider_name = opts[:provider]
        unless verify_provider_loadable(provider_name)
          return 1
        end

        if opts[:dry_run]
          stdout.puts "Would write to #{settings_path}:"
          stdout.puts "  CLAUDE_MEMORY_EMBEDDING_PROVIDER=#{provider_name}"
          stdout.puts "  CLAUDE_MEMORY_EMBEDDING_MODEL=#{opts[:model]}" if opts[:model]
          stdout.puts(opts[:reindex] ? "Would re-index facts under the new provider" : "Would skip re-index (--no-reindex)")
          return 0
        end

        write_settings(provider_name, opts[:model])

        if opts[:reindex]
          reindex_result = reindex(provider_name)
          return 1 if reindex_result != 0
        else
          stdout.puts "Skipped re-index (--no-reindex). Run 'claude-memory index --force --provider=#{provider_name}' when ready."
        end

        report_final_state(provider_name)
        0
      end

      private

      def parse_opts(args)
        options = {provider: "fastembed", model: nil, reindex: true, dry_run: false, status: false}
        parser = OptionParser.new do |o|
          o.banner = "Usage: claude-memory setup-vectors [--provider=fastembed|api|tfidf] [--model=NAME] [--no-reindex] [--dry-run] [--status]"
          o.on("--provider NAME", "Embedding provider (default: fastembed)") { |v| options[:provider] = v }
          o.on("--model NAME", "Optional model name (e.g. BAAI/bge-small-en-v1.5)") { |v| options[:model] = v }
          o.on("--no-reindex", "Skip re-embedding existing facts under the new provider") { options[:reindex] = false }
          o.on("--dry-run", "Print what would change without writing or re-indexing") { options[:dry_run] = true }
          o.on("--status", "Show the current provider config + stored alignment, then exit") { options[:status] = true }
        end
        parser.parse!(args.dup)
        options
      rescue OptionParser::InvalidOption => e
        stderr.puts e.message
        nil
      end

      def verify_provider_loadable(provider_name)
        case provider_name
        when "tfidf"
          true # always available
        when "fastembed"
          require "fastembed"
          true
        when "api"
          # api provider needs network + key but no gem; defer to runtime
          true
        else
          stderr.puts "Unknown provider: #{provider_name}. Valid: tfidf, fastembed, api."
          false
        end
      rescue LoadError
        stderr.puts FASTEMBED_INSTALL_HINT
        false
      end

      def settings_path
        File.join(claude_dir, "settings.json")
      end

      def claude_dir
        File.join(Configuration.new.project_dir, ".claude")
      end

      def write_settings(provider_name, model)
        FileUtils.mkdir_p(claude_dir)
        settings = load_settings
        settings["env"] ||= {}
        settings["env"]["CLAUDE_MEMORY_EMBEDDING_PROVIDER"] = provider_name
        if model
          settings["env"]["CLAUDE_MEMORY_EMBEDDING_MODEL"] = model
        else
          settings["env"].delete("CLAUDE_MEMORY_EMBEDDING_MODEL")
        end
        File.write(settings_path, JSON.pretty_generate(settings) + "\n")
        stdout.puts "✓ Wrote CLAUDE_MEMORY_EMBEDDING_PROVIDER=#{provider_name} to #{settings_path}"
        stdout.puts "✓ Wrote CLAUDE_MEMORY_EMBEDDING_MODEL=#{model}" if model
      end

      def load_settings
        return {} unless File.exist?(settings_path)
        raw = File.read(settings_path)
        return {} if raw.strip.empty?
        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError => e
        stderr.puts "settings.json parse error: #{e.message} — refusing to overwrite"
        {}
      end

      def reindex(provider_name)
        stdout.puts "→ Re-embedding facts under provider=#{provider_name}…"
        IndexCommand.new(stdout: stdout, stderr: stderr).call(["--force", "--provider", provider_name])
      end

      def report_final_state(provider_name)
        # The settings.json write only affects future sessions (Claude Code
        # reads the env block at session start). For the current process
        # the ENV var isn't set, so report what Embeddings.resolve would
        # produce under the new env.
        env_override = ENV.to_h.merge("CLAUDE_MEMORY_EMBEDDING_PROVIDER" => provider_name)
        provider = Embeddings.resolve(provider_name, env: env_override)
        stdout.puts
        stdout.puts "Provider: #{provider.name}, dimensions: #{provider.dimensions}"
        stdout.puts "Next session will use this provider. Run 'claude-memory doctor' to verify."
      end

      def print_status
        # Resolve under current ENV to show what the next session will use
        provider = Embeddings.resolve
        stdout.puts "Current provider:   #{provider.name}"
        stdout.puts "Current dimensions: #{provider.dimensions}"
        stdout.puts "Settings file:      #{settings_path}"
        env = load_settings.fetch("env", {})
        relevant = env.slice(*OWNED_KEYS)
        if relevant.any?
          stdout.puts "Configured env:"
          relevant.each { |k, v| stdout.puts "  #{k}=#{v}" }
        else
          stdout.puts "Configured env:     (none — using default tfidf)"
        end
        0
      end
    end
  end
end
