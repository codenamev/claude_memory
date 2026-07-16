# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Sweep::HistoricalCleanup do
  let(:db_path) { File.join(Dir.tmpdir, "historical_cleanup_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:cleanup) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#dedupe_open_conflicts" do
    let!(:repo_id) { store.find_or_create_entity(type: "repo", name: "test-repo") }

    def make_fact(object:, status: "active", predicate: "uses_database")
      store.insert_fact(subject_entity_id: repo_id, predicate: predicate,
        object_literal: object, status: status, confidence: 0.9, scope: "project")
    end

    it "keeps the earliest conflict and resolves subsequent duplicates referencing the same pair" do
      keeper_a = make_fact(object: "postgresql")
      # Simulate the pre-2026-04-24 bug: three separate disputed facts
      # plus three separate conflict rows for the same contradiction.
      dup1_b = make_fact(object: "sqlite", status: "disputed")
      dup2_b = make_fact(object: "sqlite", status: "disputed")
      dup3_b = make_fact(object: "sqlite", status: "disputed")
      keeper_conflict = store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup1_b)
      _dup_conflict_2 = store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup2_b)
      _dup_conflict_3 = store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup3_b)

      result = cleanup.dedupe_open_conflicts
      expect(result[:inspected]).to eq(3)
      expect(result[:resolved]).to eq(2)

      # Exactly the first (keeper) remains open
      expect(store.conflicts.where(status: "open").map(:id)).to eq([keeper_conflict])
      expect(store.conflicts.where(status: "resolved").count).to eq(2)
    end

    it "treats A-vs-B and B-vs-A as the same pair" do
      keeper_a = make_fact(object: "sqlite")
      dup_b = make_fact(object: "postgresql", status: "disputed")
      keeper_conflict = store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup_b)

      # Second detection with the objects swapped
      swapped_a = make_fact(object: "postgresql", status: "disputed")
      swapped_b = make_fact(object: "sqlite", status: "disputed")
      _swapped_conflict = store.insert_conflict(fact_a_id: swapped_a, fact_b_id: swapped_b)

      result = cleanup.dedupe_open_conflicts
      expect(result[:resolved]).to eq(1)
      expect(store.conflicts.where(status: "open").map(:id)).to eq([keeper_conflict])
    end

    it "does nothing when there are no duplicates" do
      keeper_a = make_fact(object: "postgresql")
      dup_b = make_fact(object: "sqlite", status: "disputed")
      store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup_b)

      result = cleanup.dedupe_open_conflicts
      expect(result[:resolved]).to eq(0)
      expect(store.conflicts.where(status: "open").count).to eq(1)
    end

    it "reassigns provenance from duplicate disputed facts onto the keeper" do
      keeper_a = make_fact(object: "postgresql")
      keeper_b = make_fact(object: "sqlite", status: "disputed")
      dup_b = make_fact(object: "sqlite", status: "disputed")
      store.insert_conflict(fact_a_id: keeper_a, fact_b_id: keeper_b)
      store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup_b)

      content_id = store.upsert_content_item(
        source: "test", text_hash: "abc", byte_len: 1,
        raw_text: "second detection"
      )
      store.insert_provenance(fact_id: dup_b, content_item_id: content_id,
        strength: "stated", quote: "second detection")

      cleanup.dedupe_open_conflicts

      # Provenance from the dup's disputed fact moves to the keeper's disputed fact.
      expect(store.provenance.where(fact_id: keeper_b).count).to eq(1)
      expect(store.provenance.where(fact_id: dup_b).count).to eq(0)
      # The duplicate disputed fact gets rejected so it stops appearing in facts_for_slot.
      expect(store.facts.where(id: dup_b).first[:status]).to eq("rejected")
    end

    it "does not write when dry_run: true" do
      keeper_a = make_fact(object: "postgresql")
      dup1_b = make_fact(object: "sqlite", status: "disputed")
      dup2_b = make_fact(object: "sqlite", status: "disputed")
      store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup1_b)
      store.insert_conflict(fact_a_id: keeper_a, fact_b_id: dup2_b)

      result = cleanup.dedupe_open_conflicts(dry_run: true)
      expect(result[:resolved]).to eq(1)
      expect(store.conflicts.where(status: "open").count).to eq(2)
      expect(result[:decisions].first[:action]).to eq(:resolve_duplicate)
    end
  end

  describe "#reclassify_references" do
    let!(:repo_id) { store.find_or_create_entity(type: "repo", name: "test-repo") }

    def make_convention(object)
      store.insert_fact(
        subject_entity_id: repo_id, predicate: "convention",
        object_literal: object, status: "active", confidence: 0.9, scope: "project"
      )
    end

    it "reclassifies LOC/star/author facts from convention to reference" do
      id_ref = make_convention("Cloud-backed Claude Code plugin (~1,195 LOC JavaScript) using Supermemory API")
      id_conv = make_convention("Use frozen_string_literal: true at the top of Ruby files")

      result = cleanup.reclassify_references
      expect(result[:reclassified]).to eq(1)
      expect(store.facts.where(id: id_ref).first[:predicate]).to eq("reference")
      expect(store.facts.where(id: id_conv).first[:predicate]).to eq("convention")
    end

    it "ignores non-convention predicates" do
      id_decision = store.insert_fact(
        subject_entity_id: repo_id, predicate: "decision",
        object_literal: "Library X is a plugin by Jane Doe with 5,000+ stars",
        status: "active", scope: "project", confidence: 0.9
      )
      result = cleanup.reclassify_references
      expect(result[:reclassified]).to eq(0)
      expect(store.facts.where(id: id_decision).first[:predicate]).to eq("decision")
    end

    it "is a no-op under dry_run" do
      id = make_convention("Tool Y has 12,000+ stars by Jane Doe")
      result = cleanup.reclassify_references(dry_run: true)
      expect(result[:reclassified]).to eq(1)
      expect(store.facts.where(id: id).first[:predicate]).to eq("convention")
    end
  end

  describe "#restore_multi_value_supersessions" do
    let!(:repo_id) { store.find_or_create_entity(type: "repo", name: "test-repo") }

    def make_fact(object, status: "active")
      id = store.insert_fact(subject_entity_id: repo_id, predicate: "uses_framework", object_literal: object)
      if status != "active"
        store.facts.where(id: id).update(status: status, valid_to: Time.now.utc.iso8601)
      end
      id
    end

    def link_supersession(new_id, old_id)
      store.insert_fact_link(from_fact_id: new_id, to_fact_id: old_id, link_type: "supersedes")
    end

    it "restores token-disjoint superseded facts" do
      active_id = make_fact("Stripe for payments")
      rails_id = make_fact("Rails 8.1", status: "superseded")
      tailwind_id = make_fact("Tailwind CSS", status: "superseded")
      link_supersession(active_id, rails_id)
      link_supersession(active_id, tailwind_id)

      result = cleanup.restore_multi_value_supersessions(predicate: "uses_framework")

      expect(result[:inspected]).to eq(2)
      expect(result[:restored]).to eq(2)
      expect(result[:skipped_ambiguous]).to eq(0)

      expect(store.facts.where(id: rails_id).get(:status)).to eq("active")
      expect(store.facts.where(id: tailwind_id).get(:status)).to eq("active")
      expect(store.facts.where(id: rails_id).get(:valid_to)).to be_nil
      expect(store.fact_links.where(to_fact_id: rails_id, link_type: "supersedes").count).to eq(0)
      expect(store.fact_links.where(to_fact_id: tailwind_id, link_type: "supersedes").count).to eq(0)
    end

    it "skips token-overlapping supersessions (likely corrections)" do
      new_id = make_fact("Rails 8.1")
      old_id = make_fact("Rails 8.0", status: "superseded")
      link_supersession(new_id, old_id)

      result = cleanup.restore_multi_value_supersessions(predicate: "uses_framework")

      expect(result[:inspected]).to eq(1)
      expect(result[:restored]).to eq(0)
      expect(result[:skipped_ambiguous]).to eq(1)
      expect(store.facts.where(id: old_id).get(:status)).to eq("superseded")
    end

    it "leaves rejected facts alone" do
      rejected_id = make_fact("react", status: "rejected")
      result = cleanup.restore_multi_value_supersessions(predicate: "uses_framework")

      expect(result[:inspected]).to eq(0)
      expect(store.facts.where(id: rejected_id).get(:status)).to eq("rejected")
    end

    it "refuses to run on a still-single-value predicate" do
      expect {
        cleanup.restore_multi_value_supersessions(predicate: "uses_database")
      }.to raise_error(ArgumentError, /still classified single-value/)
    end

    it "supports dry-run mode" do
      active_id = make_fact("Stripe")
      rails_id = make_fact("Rails 8.1", status: "superseded")
      link_supersession(active_id, rails_id)

      result = cleanup.restore_multi_value_supersessions(predicate: "uses_framework", dry_run: true)

      expect(result[:restored]).to eq(1)
      expect(result[:decisions]).to contain_exactly(
        hash_including(fact_id: rails_id, action: :restore)
      )
      expect(store.facts.where(id: rails_id).get(:status)).to eq("superseded")
    end

    it "treats rejected siblings as overlap evidence" do
      # If an identical-ish fact was explicitly rejected, don't restore.
      # Use two-token names so drop-short-tokens doesn't reduce both to
      # a single shared token (which would overlap regardless).
      active_id = make_fact("Stripe payments")
      rejected_id = make_fact("Rails stimulus", status: "rejected")
      superseded_id = make_fact("Rails stimulus extensions", status: "superseded")
      link_supersession(active_id, superseded_id)

      result = cleanup.restore_multi_value_supersessions(predicate: "uses_framework")

      expect(result[:skipped_ambiguous]).to eq(1)
      expect(store.facts.where(id: superseded_id).get(:status)).to eq("superseded")
      expect(store.facts.where(id: rejected_id).get(:status)).to eq("rejected")
    end
  end
end
