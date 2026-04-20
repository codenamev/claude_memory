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

        it "reinforces an exact duplicate instead of inserting a new row" do
          # Regression: the distiller emits uses_language=ruby on every
          # ingest cycle. Before this fix, multi-value predicates took a
          # straight :insert path regardless of existing identical facts,
          # so a project DB could accumulate 20+ `uses_language=ruby` rows.
          extraction = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_language", object: "ruby"}]
          )
          resolver.apply(extraction)

          result = resolver.apply(extraction)

          expect(result[:facts_created]).to eq(0)
          expect(result[:provenance_created]).to eq(1)

          repo_id = store.entities.where(canonical_name: "repo").get(:id)
          expect(store.facts_for_slot(repo_id, "uses_language").size).to eq(1)
        end

        it "treats case-insensitively matching objects as duplicates" do
          resolver.apply(ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_framework", object: "Rails"}]
          ))

          result = resolver.apply(ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_framework", object: "rails"}]
          ))

          expect(result[:facts_created]).to eq(0)
          expect(result[:provenance_created]).to eq(1)
        end

        it "writes fact.scope to match the call's scope argument, ignoring scope_hint override" do
          # Regression: distiller emits scope_hint: "global" when text
          # matches patterns like "always"; resolver used to treat that
          # as a scope override and wrote scope=global rows into the
          # project DB — orphaned facts invisible to global recall.
          extraction = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "uses_language", object: "ruby", scope_hint: "global"}]
          )

          resolver.apply(extraction, scope: "project")

          fact = store.facts.where(predicate: "uses_language", object_literal: "ruby").first
          expect(fact[:scope]).to eq("project")
        end

        it "logs a warning when a novel predicate is encountered" do
          logger = instance_double("Logging::Logger")
          allow(logger).to receive(:warn)
          allow(logger).to receive(:debug)
          allow(logger).to receive(:info)
          allow(ClaudeMemory).to receive(:logger).and_return(logger)

          extraction = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "totally_new_predicate", object: "foo"}]
          )
          resolver.apply(extraction)

          expect(logger).to have_received(:warn).with(
            "resolve",
            hash_including(message: "Novel predicate encountered", predicate: "totally_new_predicate")
          )
        end

        it "does not warn on known predicates" do
          logger = instance_double("Logging::Logger")
          allow(logger).to receive(:warn)
          allow(logger).to receive(:debug)
          allow(logger).to receive(:info)
          allow(ClaudeMemory).to receive(:logger).and_return(logger)

          extraction = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "convention", object: "use frozen_string_literal"}]
          )
          resolver.apply(extraction)

          expect(logger).not_to have_received(:warn)
        end

        it "canonicalizes synonym predicates before insertion" do
          # has_convention should land under the canonical "convention"
          # predicate so downstream queries and snapshot rendering find it.
          extraction = ClaudeMemory::Distill::Extraction.new(
            facts: [{subject: "repo", predicate: "has_convention", object: "use frozen_string_literal"}]
          )
          resolver.apply(extraction)

          repo_id = store.find_or_create_entity(type: "repo", name: "repo")
          convention_facts = store.facts_for_slot(repo_id, "convention")
          expect(convention_facts.size).to eq(1)
          expect(convention_facts.first[:object_literal]).to eq("use frozen_string_literal")

          has_convention_facts = store.facts_for_slot(repo_id, "has_convention")
          expect(has_convention_facts).to be_empty
        end

        it "canonicalizes primary_language to uses_language" do
          extraction = ClaudeMemory::Distill::Extraction.new(
            facts: [
              {subject: "repo", predicate: "primary_language", object: "Ruby"},
              {subject: "repo", predicate: "uses_language", object: "Python"}
            ]
          )
          resolver.apply(extraction)

          repo_id = store.find_or_create_entity(type: "repo", name: "repo")
          facts = store.facts_for_slot(repo_id, "uses_language")
          # Both facts should accumulate under uses_language (multi-value);
          # the primary_language one was canonicalized before resolution.
          expect(facts.size).to eq(2)
          expect(facts.map { |f| f[:object_literal] }).to contain_exactly("Ruby", "Python")
        end

        it "accumulates multiple uses_framework facts without supersession" do
          # Regression: uses_framework was single-value, which caused
          # multi-framework stacks (Rails + Turbo + Tailwind in the same
          # project) to silently supersede each other. Surveyed 9 real
          # project DBs where this destroyed valid knowledge.
          framework_facts = [
            {subject: "repo", predicate: "uses_framework", object: "Rails 8.1", strength: "stated"},
            {subject: "repo", predicate: "uses_framework", object: "Hotwire", strength: "stated"},
            {subject: "repo", predicate: "uses_framework", object: "Tailwind CSS", strength: "stated"}
          ]

          total_superseded = 0
          total_conflicts = 0
          framework_facts.each do |fact|
            extraction = ClaudeMemory::Distill::Extraction.new(facts: [fact])
            result = resolver.apply(extraction)
            total_superseded += result[:facts_superseded]
            total_conflicts += result[:conflicts_created]
          end

          expect(total_superseded).to eq(0)
          expect(total_conflicts).to eq(0)

          repo_id = store.find_or_create_entity(type: "repo", name: "repo")
          active = store.facts_for_slot(repo_id, "uses_framework")
          expect(active.size).to eq(3)
          expect(active.map { |f| f[:object_literal] }).to contain_exactly("Rails 8.1", "Hotwire", "Tailwind CSS")
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
