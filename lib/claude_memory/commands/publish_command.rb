# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Publishes memory snapshot to Claude Code
    class PublishCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {mode: :shared, granularity: :repo, since: nil, scope: "project"}) do |o|
          OptionParser.new do |parser|
            parser.on("--mode MODE", "Mode: shared, local, or home") { |v| o[:mode] = v.to_sym }
            parser.on("--granularity LEVEL", "Granularity: repo, paths, or nested") { |v| o[:granularity] = v.to_sym }
            parser.on("--since ISO", "Include changes since timestamp") { |v| o[:since] = v }
            parser.on("--scope SCOPE", "Scope: project or global") { |v| o[:scope] = v }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        store = manager.store_for_scope(opts[:scope])
        publish = ClaudeMemory::Publish.new(store)

        result = publish.publish!(mode: opts[:mode], granularity: opts[:granularity], since: opts[:since])

        case result[:status]
        when :updated
          stdout.puts "Published #{opts[:scope]} snapshot to #{result[:path]}"
        when :unchanged
          stdout.puts "No changes - #{result[:path]} is up to date"
        end

        manager.close
        0
      end
    end
  end
end
