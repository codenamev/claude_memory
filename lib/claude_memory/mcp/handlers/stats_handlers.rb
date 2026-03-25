# frozen_string_literal: true

module ClaudeMemory
  module MCP
    module Handlers
      # Status and statistics tool handlers
      module StatsHandlers
        def status
          result = {databases: {}}

          if @manager
            if @manager.global_exists?
              @manager.ensure_global!
              result[:databases][:global] = db_stats(@manager.global_store)
            else
              result[:databases][:global] = {exists: false}
            end

            if @manager.project_exists?
              @manager.ensure_project!
              result[:databases][:project] = db_stats(@manager.project_store)
            else
              result[:databases][:project] = {exists: false}
            end
          else
            result[:databases][:legacy] = db_stats(@legacy_store)
          end

          result[:pending_distillation] = pending_distillation_count
          result
        end

        def stats(args)
          scope = args["scope"] || "all"
          result = {scope: scope, databases: {}}

          if @manager
            if scope == "all" || scope == "global"
              if @manager.global_exists?
                @manager.ensure_global!
                result[:databases][:global] = detailed_stats(@manager.global_store)
              else
                result[:databases][:global] = {exists: false}
              end
            end

            if scope == "all" || scope == "project"
              if @manager.project_exists?
                @manager.ensure_project!
                result[:databases][:project] = detailed_stats(@manager.project_store)
              else
                result[:databases][:project] = {exists: false}
              end
            end
          else
            result[:databases][:legacy] = detailed_stats(@legacy_store)
          end

          result
        end

        private

        def pending_distillation_count
          stores = if @manager
            [@manager.global_exists? ? @manager.global_store : nil,
              @manager.project_exists? ? @manager.project_store : nil].compact
          elsif @legacy_store
            [@legacy_store]
          else
            []
          end

          stores.sum { |store| store.count_undistilled(min_length: 200) }
        end

        def db_stats(store)
          stats = {
            exists: true,
            facts_total: store.facts.count,
            facts_active: store.facts.where(status: "active").count,
            content_items: store.content_items.count,
            open_conflicts: store.conflicts.where(status: "open").count,
            schema_version: store.schema_version
          }

          vec_index = store.vector_index
          stats[:vec_available] = vec_index.available?
          stats[:vec_indexed] = vec_index.coverage_stats[:vec_indexed] if vec_index.available?

          if fts_legacy?(store)
            stats[:fts_legacy] = true
            stats[:optimization_hint] = "Run 'claude-memory compact' to reduce database size by ~40%"
          end

          stats
        end

        def fts_legacy?(store)
          row = store.db.fetch("SELECT sql FROM sqlite_master WHERE name = 'content_fts' AND type = 'table'").first
          row && !row[:sql].to_s.include?("content=''")
        rescue
          false
        end

        def detailed_stats(store)
          active_facts = store.facts.where(status: "active").count

          stats = {
            exists: true,
            facts: fact_stats(store, active_facts),
            entities: entity_stats(store),
            content_items: content_stats(store),
            provenance: provenance_stats(store, active_facts),
            conflicts: conflict_stats(store),
            schema_version: store.schema_version
          }

          stats[:vec] = vec_stats(store, active_facts)

          stats
        end

        def fact_stats(store, active_facts)
          stats = {
            total: store.facts.count,
            active: active_facts,
            superseded: store.facts.where(status: "superseded").count
          }

          if active_facts > 0
            stats[:top_predicates] = store.db[:facts]
              .where(status: "active")
              .group_and_count(:predicate)
              .order(Sequel.desc(:count))
              .limit(10)
              .all
              .map { |row| {predicate: row[:predicate], count: row[:count]} }
          end

          stats
        end

        def entity_stats(store)
          {
            total: store.entities.count,
            by_type: store.db[:entities]
              .group_and_count(:type)
              .order(Sequel.desc(:count))
              .all
              .map { |row| {type: row[:type], count: row[:count]} }
          }
        end

        def content_stats(store)
          count = store.content_items.count
          stats = {total: count}

          if count > 0
            stats[:date_range] = {
              first: store.content_items.min(:occurred_at),
              last: store.content_items.max(:occurred_at)
            }
          end

          stats
        end

        def provenance_stats(store, active_facts)
          return {facts_with_sources: 0, total_active_facts: 0, coverage_percentage: 0} if active_facts == 0

          facts_with_provenance = store.db[:provenance]
            .join(:facts, id: :fact_id)
            .where(Sequel[:facts][:status] => "active")
            .select(Sequel[:provenance][:fact_id])
            .distinct
            .count

          {
            facts_with_sources: facts_with_provenance,
            total_active_facts: active_facts,
            coverage_percentage: (facts_with_provenance * 100.0 / active_facts).round(1)
          }
        end

        def vec_stats(store, _active_facts)
          vec_index = store.vector_index
          result = {available: vec_index.available?}
          result.merge!(vec_index.coverage_stats) if vec_index.available?
          result
        end

        def conflict_stats(store)
          open = store.conflicts.where(status: "open").count
          resolved = store.conflicts.where(status: "resolved").count

          {open: open, resolved: resolved, total: open + resolved}
        end
      end
    end
  end
end
