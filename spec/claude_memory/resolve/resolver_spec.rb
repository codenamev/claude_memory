# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Resolve::Resolver do
  let(:db_path) { File.join(Dir.tmpdir, "resolver_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:resolver) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#apply" do
    context "with entities" do
      it "creates entities from extraction" do
        extraction = ClaudeMemory::Distill::Extraction.new(
          entities: [{type: "database", name: "postgresql"}]
        )

        result = resolver.apply(extraction)
        expect(result[:entities_created]).to eq(1)
      end

      it "deduplicates entities in same extraction" do
        extraction = ClaudeMemory::Distill::Extraction.new(
          entities: [{type: "database", name: "postgresql"}, {type: "database", name: "postgresql"}]
        )

        result = resolver.apply(extraction)
        expect(result[:entities_created]).to eq(1)
      end
    end

    context "with facts" do
      it "creates facts from extraction" do
        extraction = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "convention", object: "use snake_case", quote: "the quote"}]
        )

        result = resolver.apply(extraction)
        expect(result[:facts_created]).to eq(1)
        expect(result[:provenance_created]).to eq(1)
      end

      context "for single-cardinality predicates" do
        it "supersedes existing fact when signal is present" do
          extraction1 = ClaudeMemory::Distill::Extraction.new(
            entities: [{type: "database", name: "mysql"}],
            facts: [{subject: "repo", predicate: "uses_database", object: "mysql", strength: "stated"}]
          )
          resolver.apply(extraction1)

          extraction2 = ClaudeMemory::Distill::Extraction.new(
            entities: [{type: "database", name: "postgresql"}],
            facts: [{subject: "repo", predicate: "uses_database", object: "postgresql", strength: "stated", supersedes: true}]
          )
          result = resolver.apply(extraction2)

          expect(result[:facts_superseded]).to eq(1)
          expect(result[:facts_created]).to eq(1)

          repo_id = store.find_or_create_entity(type: "repo", name: "repo")
          active_facts = store.facts_for_slot(repo_id, "uses_database")
          expect(active_facts.size).to eq(1)
          expect(active_facts.first[:object_literal]).to eq("postgresql")

          superseded_facts = store.facts_for_slot(repo_id, "uses_database", status: "superseded")
          expect(superseded_facts.size).to eq(1)
        end

        it "creates conflict without supersession signal" do
          extraction1 = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_database", object: "mysql", strength: "stated"}]
          )
          resolver.apply(extraction1)

          extraction2 = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_database", object: "postgresql", strength: "inferred"}]
          )
          result = resolver.apply(extraction2)

          expect(result[:conflicts_created]).to eq(1)
          expect(result[:facts_created]).to eq(0)

          conflicts = store.open_conflicts
          expect(conflicts.size).to eq(1)
        end

        it "adds provenance to matching existing fact" do
          extraction1 = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_database", object: "postgresql", strength: "stated"}]
          )
          resolver.apply(extraction1)

          extraction2 = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_database", object: "PostgreSQL", strength: "stated"}]
          )
          result = resolver.apply(extraction2)

          expect(result[:facts_created]).to eq(0)
          expect(result[:provenance_created]).to eq(1)
          expect(result[:conflicts_created]).to eq(0)
        end
      end

      context "for multi-cardinality predicates" do
        it "allows multiple facts" do
          extraction1 = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "convention", object: "use snake_case"}]
          )
          resolver.apply(extraction1)

          extraction2 = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "convention", object: "indent with 2 spaces"}]
          )
          result = resolver.apply(extraction2)

          expect(result[:facts_created]).to eq(1)
          expect(result[:conflicts_created]).to eq(0)
        end
      end
    end

    context "with provenance" do
      it "links facts to content items" do
        content_id = store.upsert_content_item(
          source: "test",
          text_hash: "abc",
          byte_len: 10,
          raw_text: "test content"
        )

        extraction = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "convention", object: "test", quote: "the quote"}]
        )

        resolver.apply(extraction, content_item_id: content_id)

        repo_id = store.find_or_create_entity(type: "repo", name: "repo")
        facts = store.facts_for_slot(repo_id, "convention")
        provenance = store.provenance_for_fact(facts.first[:id])

        expect(provenance.first[:content_item_id]).to eq(content_id)
        expect(provenance.first[:quote]).to eq("the quote")
      end
    end

    context "transaction safety" do
      it "rolls back fact creation if provenance insertion fails" do
        extraction = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "convention", object: "test", quote: "quote"}]
        )

        # Mock provenance insertion to fail
        allow(store).to receive(:insert_provenance).and_raise(StandardError, "Provenance failed")

        expect {
          resolver.apply(extraction)
        }.to raise_error(StandardError, "Provenance failed")

        # Verify rollback - no facts should be created
        repo_id = store.find_or_create_entity(type: "repo", name: "repo")
        facts = store.facts_for_slot(repo_id, "convention")
        expect(facts).to be_empty
      end

      it "rolls back supersession if fact link creation fails" do
        # Create initial fact
        extraction1 = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "uses_database", object: "mysql", strength: "stated"}]
        )
        resolver.apply(extraction1)

        # Attempt supersession with failing fact link
        extraction2 = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "uses_database", object: "postgresql", strength: "stated", supersedes: true}]
        )

        allow(store).to receive(:insert_fact_link).and_raise(StandardError, "Link failed")

        expect {
          resolver.apply(extraction2)
        }.to raise_error(StandardError, "Link failed")

        # Verify rollback - old fact should still be active, no new fact created
        repo_id = store.find_or_create_entity(type: "repo", name: "repo")
        active_facts = store.facts_for_slot(repo_id, "uses_database")
        expect(active_facts.size).to eq(1)
        expect(active_facts.first[:object_literal]).to eq("mysql")
        expect(active_facts.first[:status]).to eq("active")

        superseded_facts = store.facts_for_slot(repo_id, "uses_database", status: "superseded")
        expect(superseded_facts).to be_empty
      end

      it "rolls back conflict creation if conflict insertion fails" do
        # Create initial fact
        extraction1 = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "uses_database", object: "mysql", strength: "stated"}]
        )
        resolver.apply(extraction1)

        # Attempt conflict with failing conflict insertion
        extraction2 = ClaudeMemory::Distill::Extraction.new(
          facts: [{subject: "repo", predicate: "uses_database", object: "postgresql", strength: "inferred", quote: "quote"}]
        )

        # Mock insert_conflict to fail
        allow(store).to receive(:insert_conflict).and_raise(StandardError, "Conflict insertion failed")

        expect {
          resolver.apply(extraction2)
        }.to raise_error(StandardError, "Conflict insertion failed")

        # Verify rollback - no conflicting fact should be created
        conflicts = store.open_conflicts
        expect(conflicts).to be_empty

        repo_id = store.find_or_create_entity(type: "repo", name: "repo")
        facts = store.facts_for_slot(repo_id, "uses_database", status: "disputed")
        expect(facts).to be_empty
      end
    end
  end
end
