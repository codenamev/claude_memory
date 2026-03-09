# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Commands
    # Exports facts, entities, and provenance to JSON for backup or migration.
    # Output goes to stdout (default) or a file via --output.
    class ExportCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {scope: "project", status: "active", output: nil, pretty: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory export [options]"
            parser.on("--scope SCOPE", %w[all global project],
              "Scope: project (default), global, or all") { |v| o[:scope] = v }
            parser.on("--status STATUS", %w[active all],
              "Fact status: active (default) or all") { |v| o[:status] = v }
            parser.on("--output FILE", "Write to file instead of stdout") { |v| o[:output] = v }
            parser.on("--pretty", "Pretty-print JSON output") { o[:pretty] = true }
          end
        end
        return 1 if opts.nil?

        manager = ClaudeMemory::Store::StoreManager.new
        data = build_export(manager, opts[:scope], opts[:status])
        manager.close

        json = opts[:pretty] ? JSON.pretty_generate(data) : JSON.generate(data)

        if opts[:output]
          File.write(opts[:output], json)
          stderr.puts "Exported #{data[:facts].size} facts to #{opts[:output]}"
        else
          stdout.puts json
        end

        0
      end

      private

      def build_export(manager, scope, status_filter)
        export = {
          version: ClaudeMemory::VERSION,
          exported_at: Time.now.utc.iso8601,
          scope: scope,
          entities: [],
          facts: []
        }

        if scope == "all" || scope == "global"
          if manager.global_exists?
            manager.ensure_global!
            collect_from_store(manager.global_store, "global", status_filter, export)
          end
        end

        if scope == "all" || scope == "project"
          if manager.project_exists?
            manager.ensure_project!
            collect_from_store(manager.project_store, "project", status_filter, export)
          end
        end

        export
      end

      def collect_from_store(store, source_label, status_filter, export)
        # Collect entities (batch load all for lookup)
        all_entities = store.entities.all
        entities_by_id = all_entities.each_with_object({}) { |e, h| h[e[:id]] = e }

        all_entities.each do |entity|
          export[:entities] << {
            id: entity[:id],
            type: entity[:type],
            name: entity[:canonical_name],
            source: source_label
          }
        end

        # Collect facts with provenance (batch load to avoid N+1)
        facts_ds = store.facts
        facts_ds = facts_ds.where(status: "active") if status_filter == "active"
        all_facts = facts_ds.all

        fact_ids = all_facts.map { |f| f[:id] }
        provenance_by_fact = store.provenance.where(fact_id: fact_ids).all
          .group_by { |p| p[:fact_id] }

        all_facts.each do |fact|
          subject = entities_by_id[fact[:subject_entity_id]]
          receipts = provenance_by_fact[fact[:id]] || []

          export[:facts] << {
            id: fact[:id],
            docid: fact[:docid],
            subject: subject&.[](:canonical_name),
            predicate: fact[:predicate],
            object: fact[:object_literal],
            status: fact[:status],
            confidence: fact[:confidence],
            scope: fact[:scope],
            valid_from: fact[:valid_from],
            valid_to: fact[:valid_to],
            created_at: fact[:created_at],
            source: source_label,
            receipts: receipts.map { |r|
              {quote: r[:quote], strength: r[:strength]}
            }
          }
        end
      end
    end
  end
end
