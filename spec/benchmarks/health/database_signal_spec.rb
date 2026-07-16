# frozen_string_literal: true

# Codifies the signal-health thresholds from the 2026-05-21 memory audit
# (see docs/memory_audit_2026-05-21.md Phase 4.2). Runs against the
# *live* project database, not a fixture — the point is to detect when
# the gem's own dogfood DB drifts back into contamination.
#
# Tag: :benchmark (excluded from default rspec; run with `bundle exec
# rspec spec/benchmarks/health/ --tag benchmark`).
#
# Thresholds and rationale:
#   - Zero open conflicts on main. Any open conflict in the active DB
#     means single-cardinality resolution has unresolved disputes.
#   - At most 1 active fact per single-cardinality predicate. The
#     contract is "at most one"; >1 is a resolver/sweep bug.
#   - Project conventions reachable via memory.conventions ≥ 1. Pre-fix
#     the shortcut returned only global facts; this guards the
#     regression.
#   - Project decisions returned by memory.decisions contain only
#     `decision`-predicate facts. Pre-fix the shortcut returned
#     `uses_database` rows too.

require_relative "../benchmark_helper"

RSpec.describe "memory database signal health", :benchmark do
  # Skip the entire suite unless the real committed `.claude/memory.sqlite3`
  # is present as an actual SQLite file. Two cases make it unavailable:
  #   1. Absent — the dogfood DB is gitignored/untracked as of the
  #      2026-06-27 "untrack machine-local state" change (ae077b7), so CI
  #      and fresh clones simply don't have the file.
  #   2. An unresolved git-lfs pointer — older checkouts LFS-tracked the DB,
  #      and the project's LFS blobs aren't reliably on the GitHub LFS
  #      server, so LFS-less CI checkouts see the pointer text instead.
  # In both cases the signal-health contracts have nothing real to assert
  # against; running them would fail on unrelated changes (an empty DB trips
  # the "≥ 5 active facts" sanity floor; a pointer raises "file is not a
  # database"). These contracts only mean something against the live DB —
  # run locally to validate them before tagging a release (docs/api_stability.md §7).
  before(:all) do
    project_db = ClaudeMemory::Configuration.new.project_db_path
    live_db = File.exist?(project_db) &&
      File.binread(project_db, 16).to_s.start_with?("SQLite format 3")
    unless live_db
      skip "skipping: #{project_db} is absent or not a SQLite file (dogfood DB is untracked/gitignored, or an unresolved git-lfs pointer). Run locally against the live DB to validate signal contracts."
    end
  end

  let(:manager) { ClaudeMemory::Store::StoreManager.new }
  let(:project_store) { manager.tap(&:ensure_project!).project_store }
  let(:global_store) { manager.tap(&:ensure_global!).global_store }

  after { manager.close }

  describe "open conflicts" do
    it "has zero open conflicts in the project DB" do
      expect(project_store.open_conflicts).to be_empty,
        "found open conflicts: #{project_store.open_conflicts.map { |c| c[:id] }.inspect}"
    end

    it "has zero open conflicts in the global DB" do
      expect(global_store.open_conflicts).to be_empty
    end
  end

  describe "single-cardinality predicate contracts" do
    %w[uses_database deployment_platform auth_method].each do |predicate|
      it "has at most one active fact for #{predicate}" do
        count = project_store.facts.where(status: "active", predicate: predicate).count
        expect(count).to be <= 1,
          "predicate=#{predicate} has #{count} active facts; single-cardinality contract violated"
      end
    end
  end

  describe "shortcut tool signal (post-2026-05-21 audit Phase 3)" do
    it "memory.conventions returns project conventions, not only global" do
      project_convention_count = project_store.facts
        .where(status: "active", predicate: "convention")
        .count

      skip "no project conventions to test against" if project_convention_count.zero?

      results = ClaudeMemory::Shortcuts.conventions(manager, limit: 50)
      project_sources = results.count { |r| r[:source] == "project" }

      expect(project_sources).to be > 0,
        "memory.conventions returned 0 project-scope facts despite #{project_convention_count} existing"
    end

    it "memory.decisions returns only `decision` predicate, not `uses_*`" do
      results = ClaudeMemory::Shortcuts.decisions(manager, limit: 50)
      predicates = results.map { |r| r[:fact][:predicate] }.uniq

      non_decision = predicates - ["decision"]
      expect(non_decision).to be_empty,
        "memory.decisions leaked non-decision predicates: #{non_decision.inspect}"
    end

    it "memory.architecture only returns architecture + stack-shaping predicates" do
      allowed = ClaudeMemory::Shortcuts::SHORTCUTS[:architecture][:predicates]
      results = ClaudeMemory::Shortcuts.architecture(manager, limit: 50)
      predicates = results.map { |r| r[:fact][:predicate] }.uniq

      leaked = predicates - allowed
      expect(leaked).to be_empty,
        "memory.architecture leaked unallowed predicates: #{leaked.inspect}"
    end
  end

  describe "distillation backlog" do
    it "has fewer than 100 undistilled content items (hard fail threshold)" do
      distilled_ids = project_store.ingestion_metrics.select(:content_item_id).distinct
      pending = project_store.content_items.exclude(id: distilled_ids).count

      expect(pending).to be < 100,
        "distillation backlog is #{pending}; re-ingestion is re-extracting the same content"
    end
  end

  describe "active fact count sanity" do
    it "has more than 5 active project facts (sanity floor)" do
      # A radically empty DB suggests an over-aggressive bulk reject or a
      # broken ingest pipeline. Below 5 means the project effectively has
      # no memory; surface it loudly.
      count = project_store.facts.where(status: "active").count
      expect(count).to be >= 5,
        "only #{count} active project facts; suspect ingest broken or DB nuked"
    end
  end
end
