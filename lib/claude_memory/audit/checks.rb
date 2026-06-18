# frozen_string_literal: true

module ClaudeMemory
  module Audit
    # Individual audit checks. Each method takes a Store::StoreManager and
    # returns an Array<Finding>. Checks must be read-only — write
    # operations belong in dedicated commands the user opts into.
    #
    # Adding a new check:
    #   1. Define a method here with an explicit C### id assignment.
    #   2. Append the method name to Runner::CHECK_METHODS.
    #   3. Document it in docs/audit_runbook.md.
    module Checks
      module_function

      # C001 — Open conflicts in either DB.
      def open_conflicts(manager)
        findings = []
        {project: manager.store_if_exists("project"), global: manager.store_if_exists("global")}.each do |scope, store|
          next unless store
          conflicts = store.open_conflicts
          next if conflicts.empty?
          findings << Finding.new(
            id: "C001",
            severity: :error,
            title: "#{conflicts.size} open conflict(s) in #{scope} DB",
            detail: "Open conflicts indicate unresolved single-cardinality disputes. Each will keep re-firing until the losing fact is rejected.",
            suggestion: "claude-memory conflicts && claude-memory reject <fact_id>",
            fact_ids: conflicts.flat_map { |c| [c[:fact_a_id], c[:fact_b_id]] }.uniq
          )
        end
        findings
      end

      # C002 — Single-cardinality predicates with > 1 active fact.
      SINGLE_CARDINALITY_PREDICATES = %w[uses_database deployment_platform auth_method].freeze

      def single_cardinality_multiplicity(manager)
        store = manager.store_if_exists("project")
        return [] unless store

        SINGLE_CARDINALITY_PREDICATES.flat_map do |predicate|
          rows = store.facts.where(status: "active", predicate: predicate).all
          next [] if rows.size <= 1
          [Finding.new(
            id: "C002",
            severity: :error,
            title: "predicate=#{predicate} has #{rows.size} active facts (single-cardinality)",
            detail: "Single-cardinality predicates must have at most one active value. Multiple actives mean resolver dropped a supersession or distillation produced contradictory claims.",
            suggestion: "Inspect with: claude-memory explain <fact_id>. Reject the wrong ones: claude-memory reject <fact_id>",
            fact_ids: rows.map { |r| r[:id] }
          )]
        end
      end

      # C003 — Distillation backlog (warn ≥ 25, error ≥ 100).
      def distillation_backlog(manager)
        store = manager.store_if_exists("project")
        return [] unless store
        distilled_ids = store.ingestion_metrics.select(:content_item_id).distinct
        pending = store.content_items.exclude(id: distilled_ids).count
        return [] if pending < 25

        severity = (pending >= 100) ? :error : :warn
        [Finding.new(
          id: "C003",
          severity: severity,
          title: "#{pending} content items not yet deeply distilled",
          detail: "Backlog grows when SessionStart distillation prompts aren't acknowledged with memory.mark_distilled. A large backlog means the same text gets re-extracted across sessions, increasing hallucination rate.",
          suggestion: "Triage with /distill-transcripts (interactive) OR mark all distilled if you accept the backlog is noise: claude-memory sweep --mark-all-distilled",
          fact_ids: []
        )]
      end

      # C004 — memory.decisions leaking non-decision predicates.
      def shortcut_decision_leak(manager)
        results = Shortcuts.decisions(manager, limit: 50)
        leaked = results.map { |r| r[:fact][:predicate] }.uniq - ["decision"]
        return [] if leaked.empty?

        [Finding.new(
          id: "C004",
          severity: :error,
          title: "memory.decisions returns non-decision predicates: #{leaked.inspect}",
          detail: "memory.decisions should return only `decision`-predicate facts. Predicate leakage suggests the shortcut implementation has regressed back to text-search filtering (pre-2026-05-21 audit).",
          suggestion: "Inspect lib/claude_memory/shortcuts.rb — SHORTCUTS[:decisions][:predicates] should equal ['decision']. Run `bundle exec rspec spec/claude_memory/shortcuts_spec.rb`.",
          fact_ids: results.select { |r| leaked.include?(r[:fact][:predicate]) }.map { |r| r[:fact][:id] }
        )]
      end

      # C005 — memory.conventions returns no project facts despite project conventions existing.
      def shortcut_convention_scope(manager)
        project_store = manager.store_if_exists("project")
        return [] unless project_store
        project_count = project_store.facts.where(status: "active", predicate: "convention").count
        return [] if project_count.zero?

        results = Shortcuts.conventions(manager, limit: 50)
        project_returned = results.count { |r| r[:source] == "project" }
        return [] if project_returned > 0

        [Finding.new(
          id: "C005",
          severity: :warn,
          title: "memory.conventions returned 0 project facts despite #{project_count} project conventions existing",
          detail: "Pre-2026-05-21 audit, memory.conventions was hardcoded to scope=global. If you're seeing 0 project facts in a project with conventions, the shortcut has regressed.",
          suggestion: "Check Shortcuts.collect_facts in lib/claude_memory/shortcuts.rb. Re-run `bundle exec rspec spec/claude_memory/shortcuts_spec.rb`.",
          fact_ids: []
        )]
      end

      # C006 — Duplicate global convention candidates (near-identical text).
      def duplicate_global_conventions(manager)
        store = manager.store_if_exists("global")
        return [] unless store
        rows = store.facts.where(status: "active", predicate: "convention").select(:id, :object_literal).all
        return [] if rows.size < 2

        # Group by normalized object text (lowercased, stripped of leading
        # "uses"/"prefers"/punctuation). Pairs with the same normalized
        # key are likely near-duplicates.
        groups = rows.group_by { |r| normalize_convention(r[:object_literal]) }
        dupe_groups = groups.select { |_, list| list.size > 1 }
        return [] if dupe_groups.empty?

        [Finding.new(
          id: "C006",
          severity: :info,
          title: "#{dupe_groups.size} near-duplicate global convention group(s)",
          detail: "Multiple global conventions normalize to the same phrasing. Pick the cleanest and reject the rest to keep memory.conventions output tight.",
          suggestion: "Review with: claude-memory recall <concept> --scope=global. Reject duplicates: claude-memory reject <fact_id>",
          fact_ids: dupe_groups.values.flatten.map { |r| r[:id] }
        )]
      end

      # C007 — Bare-conclusion decisions/conventions (no reason clause).
      def bare_conclusion_rate(manager)
        store = manager.store_if_exists("project")
        return [] unless store
        detector = Distill::BareConclusionDetector.new
        rows = store.facts.where(status: "active", predicate: %w[decision convention]).select(:id, :predicate, :object_literal).all
        bare = rows.select { |r| detector.bare_conclusion?(predicate: r[:predicate], object_literal: r[:object_literal]) }
        return [] if bare.empty?

        ratio = bare.size.to_f / rows.size
        return [] if ratio < 0.3

        [Finding.new(
          id: "C007",
          severity: :info,
          title: "#{(ratio * 100).round}% of decisions/conventions lack reason clauses (#{bare.size}/#{rows.size})",
          detail: "Facts without 'because/so that/to avoid/...' lose their justification once context fades. Bare conclusions are dead weight when the team grows or you revisit a year later.",
          suggestion: "Inspect with: claude-memory explain <fact_id>. Reject low-value bare facts or rewrite with reason clauses via memory.store_extraction.",
          fact_ids: bare.map { |r| r[:id] }
        )]
      end

      # C008 — Project DB starvation (< 5 active facts may indicate broken ingest).
      def project_starvation(manager)
        store = manager.store_if_exists("project")
        return [] unless store
        count = store.facts.where(status: "active").count
        return [] if count >= 5

        [Finding.new(
          id: "C008",
          severity: :warn,
          title: "Only #{count} active project fact(s)",
          detail: "A nearly-empty project DB suggests either a fresh install (ignore) OR a broken ingest pipeline / overzealous rejection. Verify hooks are firing: claude-memory doctor.",
          suggestion: "claude-memory doctor; claude-memory stats; check .claude/settings.json hook configuration.",
          fact_ids: []
        )]
      end

      # C009 — Auto-memory drift (markdown files newer than project DB facts).
      def auto_memory_unimported(manager)
        config = Configuration.new
        dir = Hook::AutoMemoryMirror.default_dir(config.project_dir, config.claude_config_dir)
        return [] unless Dir.exist?(dir)

        md_files = Dir.glob(File.join(dir, "*.md")).reject { |f| File.basename(f) == "MEMORY.md" }
        return [] if md_files.empty?

        store = manager.store_if_exists("project")
        return [] unless store

        # Look for auto_memory_import content items as evidence of prior
        # import. Count files that would be new on the next import.
        imported_count = store.content_items.where(source: "auto_memory_import").count
        net_new = md_files.size - imported_count
        return [] if net_new <= 0

        [Finding.new(
          id: "C009",
          severity: :info,
          title: "#{net_new} auto-memory file(s) not yet imported",
          detail: "~/.claude/projects/<slug>/memory/*.md files contain durable knowledge that isn't reachable via memory.recall until imported. AutoMemoryMirror only surfaces them transiently at SessionStart.",
          suggestion: "Preview: claude-memory import-auto-memory --dry-run. Import: claude-memory import-auto-memory.",
          fact_ids: []
        )]
      end

      # C010 — Recurring single-cardinality churn (history shows the same
      # predicate has accumulated many superseded/disputed facts — sign of
      # a persistent contamination source).
      CHURN_THRESHOLD = 5

      def single_cardinality_churn(manager)
        store = manager.store_if_exists("project")
        return [] unless store

        SINGLE_CARDINALITY_PREDICATES.flat_map do |predicate|
          non_active = store.facts
            .where(predicate: predicate, status: %w[superseded disputed rejected])
            .count
          next [] if non_active < CHURN_THRESHOLD

          [Finding.new(
            id: "C010",
            severity: :warn,
            title: "predicate=#{predicate} shows churn: #{non_active} historical non-active facts",
            detail: "Repeated supersession/dispute on a single-cardinality predicate usually means a contamination source (e.g., example text in CLAUDE.md or docs) keeps re-introducing the same hallucination.",
            suggestion: "Find the contamination source: claude-memory recall <bad_value> --scope=project. Wrap the trigger text in <no-memory> tags. See docs/audit_runbook.md.",
            fact_ids: []
          )]
        end
      end

      # Scopes whose stores carry an observations table. Observation checks
      # iterate both DBs because observations may be project- or global-scoped.
      OBSERVATION_SCOPES = %i[project global].freeze

      # Valid observation lifecycle states. Anything else means a writer or
      # migration stamped a status the resolver/reflector never produce.
      OBSERVATION_STATUSES = %w[active consolidated expired].freeze

      def observation_stores(manager)
        OBSERVATION_SCOPES
          .map { |scope| [scope, manager.store_if_exists(scope.to_s)] }
          .reject { |_, store| store.nil? }
      end

      # C011 — Orphaned observations (provenance points at a missing content item).
      def orphaned_observations(manager)
        observation_stores(manager).flat_map do |scope, store|
          content_ids = store.content_items.select(:id)
          orphans = store.observations
            .exclude(source_content_item_id: nil)
            .exclude(source_content_item_id: content_ids)
            .select(:id)
            .all
          next [] if orphans.empty?

          [Finding.new(
            id: "C011",
            severity: :warn,
            title: "#{orphans.size} observation(s) in #{scope} DB reference a missing content item",
            detail: "An observation's source_content_item_id should point at the content_items row it was distilled from. A dangling pointer means the source row was pruned or never existed, so the observation's provenance can no longer be explained.",
            suggestion: "Inspect with memory.observations. These rows are append-only; if the provenance is unrecoverable, consolidate or expire them via the Reflector (PreCompact/SessionEnd) rather than deleting.",
            fact_ids: orphans.map { |r| r[:id] }
          )]
        end
      end

      # C012 — Promotion consistency (promoted_at ⇔ promoted_fact_id, fact must exist + be active).
      def observation_promotion_consistency(manager)
        observation_stores(manager).flat_map do |scope, store|
          active_fact_ids = store.facts.where(status: "active").select(:id)

          missing_fact_id = store.observations
            .exclude(promoted_at: nil)
            .where(promoted_fact_id: nil)
            .select(:id).all
          dangling_fact = store.observations
            .exclude(promoted_fact_id: nil)
            .exclude(promoted_fact_id: store.facts.select(:id))
            .select(:id, :promoted_fact_id).all
          inactive_fact = store.observations
            .exclude(promoted_fact_id: nil)
            .exclude(promoted_fact_id: active_fact_ids)
            .exclude(promoted_fact_id: dangling_fact.map { |r| r[:promoted_fact_id] })
            .select(:id, :promoted_fact_id).all
          missing_timestamp = store.observations
            .exclude(promoted_fact_id: nil)
            .where(promoted_at: nil)
            .select(:id).all

          obs_ids = (missing_fact_id + dangling_fact + inactive_fact + missing_timestamp).map { |r| r[:id] }.uniq
          next [] if obs_ids.empty?

          problems = []
          problems << "#{missing_fact_id.size} promoted but missing promoted_fact_id" unless missing_fact_id.empty?
          problems << "#{dangling_fact.size} promoted_fact_id pointing at a non-existent fact" unless dangling_fact.empty?
          problems << "#{inactive_fact.size} promoted into a non-active fact" unless inactive_fact.empty?
          problems << "#{missing_timestamp.size} have promoted_fact_id but no promoted_at" unless missing_timestamp.empty?

          [Finding.new(
            id: "C012",
            severity: :error,
            title: "#{obs_ids.size} observation(s) in #{scope} DB have inconsistent promotion state",
            detail: "Promotion must be atomic: a promoted observation has both promoted_at set and promoted_fact_id pointing at an existing, active fact. Violations (#{problems.join("; ")}) mean mark_observation_promoted ran partially or the target fact was later rejected/superseded, leaving the observation pointing at nothing usable.",
            suggestion: "Inspect the fact with claude-memory explain <fact_id>. If the fact was intentionally rejected, the observation should be re-opened for re-promotion via memory.promote_observation; if mark_observation_promoted half-ran, re-run promotion.",
            fact_ids: obs_ids
          )]
        end
      end

      # C013 — Tombstone-chain validity (consolidated_into must point to a real,
      # non-self row and a consolidated observation must not stay active).
      def observation_tombstone_chain(manager)
        observation_stores(manager).flat_map do |scope, store|
          obs_ids = store.observations.select(:id)

          dangling = store.observations
            .exclude(consolidated_into: nil)
            .exclude(consolidated_into: obs_ids)
            .select(:id, :consolidated_into).all
          self_link = store.observations
            .exclude(consolidated_into: nil)
            .where(Sequel[:consolidated_into] => Sequel[:id])
            .select(:id).all
          active_but_tombstoned = store.observations
            .exclude(consolidated_into: nil)
            .where(status: "active")
            .select(:id).all
          consolidated_without_link = store.observations
            .where(status: "consolidated", consolidated_into: nil)
            .select(:id).all

          flagged = (dangling + self_link + active_but_tombstoned + consolidated_without_link).map { |r| r[:id] }.uniq
          next [] if flagged.empty?

          problems = []
          problems << "#{dangling.size} consolidated_into → missing observation" unless dangling.empty?
          problems << "#{self_link.size} consolidated_into self-link" unless self_link.empty?
          problems << "#{active_but_tombstoned.size} active yet have a consolidated_into target" unless active_but_tombstoned.empty?
          problems << "#{consolidated_without_link.size} status=consolidated with no consolidated_into keeper" unless consolidated_without_link.empty?

          [Finding.new(
            id: "C013",
            severity: :error,
            title: "#{flagged.size} observation(s) in #{scope} DB have a broken tombstone chain",
            detail: "Tombstoning is append-only: a superseded observation gets status=consolidated and consolidated_into pointing at the surviving keeper. Violations (#{problems.join("; ")}) corrupt the lineage — recall could surface a tombstoned row, or a consolidated row could orphan its history.",
            suggestion: "Inspect with memory.observations. Re-run the deterministic Reflector (fires on PreCompact/SessionEnd) to re-derive consolidation; a self-link or active+tombstoned row indicates a Reflector bug — file it rather than hand-editing the append-only table.",
            fact_ids: flagged
          )]
        end
      end

      # C014 — Status / corroboration sanity (known status set, corroboration ≥ 1).
      def observation_status_corroboration(manager)
        observation_stores(manager).flat_map do |scope, store|
          bad_status = store.observations
            .exclude(status: OBSERVATION_STATUSES)
            .select(:id).all
          bad_corroboration = store.observations
            .where { corroboration_count < 1 }
            .select(:id).all

          flagged = (bad_status + bad_corroboration).map { |r| r[:id] }.uniq
          next [] if flagged.empty?

          problems = []
          problems << "#{bad_status.size} with status outside #{OBSERVATION_STATUSES.inspect}" unless bad_status.empty?
          problems << "#{bad_corroboration.size} with corroboration_count < 1" unless bad_corroboration.empty?

          [Finding.new(
            id: "C014",
            severity: :warn,
            title: "#{flagged.size} observation(s) in #{scope} DB have invalid status/corroboration",
            detail: "Every observation should carry a known lifecycle status (#{OBSERVATION_STATUSES.join("/")}) and at least one sighting (corroboration_count ≥ 1; a fresh insert counts as 1). Violations (#{problems.join("; ")}) break the promotion gate (which keys off corroboration) and the recall filters (which key off status).",
            suggestion: "Inspect with memory.observations. A corroboration_count < 1 means increment_corroboration math went negative; an unknown status means a migration or external writer bypassed insert_observation. Re-derive via the Reflector if possible.",
            fact_ids: flagged
          )]
        end
      end

      def normalize_convention(text)
        text.to_s
          .downcase
          .gsub(/\b(?:uses|prefers|always|never)\b/, "")
          .gsub(/[[:punct:]]/, "")
          .gsub(/\s+/, " ")
          .strip
      end
    end
  end
end
