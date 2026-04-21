# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe ClaudeMemory::Hook::ContextInjector do
  let(:tmpdir) { Dir.mktmpdir("context_injector_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:project_path) { tmpdir }

  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: project_path
    )
  end

  let(:injector) { described_class.new(manager) }

  before { manager.ensure_both! }

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def create_fact_with_content(store, predicate, object, text, scope: "project")
    content_id = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      raw_text: text
    )

    fts = ClaudeMemory::Index::LexicalFTS.new(store)
    fts.index_content_item(content_id, text)

    entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
    fact_id = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      status: "active",
      scope: scope,
      project_path: (scope == "project") ? project_path : nil
    )

    store.insert_provenance(
      fact_id: fact_id,
      content_item_id: content_id,
      quote: text,
      strength: "stated"
    )

    fact_id
  end

  describe "#generate_context" do
    context "with no facts" do
      it "returns nil" do
        expect(injector.generate_context).to be_nil
      end
    end

    context "source filtering for distillation prompt" do
      before do
        # Create undistilled content long enough to trigger distillation prompt
        store = manager.project_store
        store.upsert_content_item(
          source: "test",
          session_id: "sess-undistilled",
          text_hash: Digest::SHA256.hexdigest("a" * 300),
          byte_len: 300,
          raw_text: "a" * 300
        )
      end

      it "includes distillation prompt when source is nil (backward compat)" do
        inj = described_class.new(manager, source: nil)
        context = inj.generate_context
        expect(context).to include("Pending Knowledge Extraction")
      end

      it "requires a reason clause in the extraction prompt" do
        inj = described_class.new(manager, source: "startup")
        context = inj.generate_context
        expect(context).to include("Reasoning requirement")
        expect(context).to match(/because|so that/)
      end

      it "includes distillation prompt when source is 'startup'" do
        inj = described_class.new(manager, source: "startup")
        context = inj.generate_context
        expect(context).to include("Pending Knowledge Extraction")
      end

      it "includes distillation prompt when source is 'resume'" do
        inj = described_class.new(manager, source: "resume")
        context = inj.generate_context
        expect(context).to include("Pending Knowledge Extraction")
      end

      it "includes distillation prompt when source is 'clear'" do
        inj = described_class.new(manager, source: "clear")
        context = inj.generate_context
        expect(context).to include("Pending Knowledge Extraction")
      end

      it "skips distillation prompt when source is 'compact'" do
        inj = described_class.new(manager, source: "compact")
        context = inj.generate_context
        expect(context).to be_nil
      end

      it "skips distillation prompt for unknown non-fresh sources" do
        inj = described_class.new(manager, source: "other")
        context = inj.generate_context
        expect(context).to be_nil
      end
    end

    context "with decision facts" do
      before do
        create_fact_with_content(
          manager.project_store,
          "decision",
          "Use PostgreSQL for the database",
          "decision constraint Use PostgreSQL for the database"
        )
      end

      it "includes decisions in context" do
        context = injector.generate_context
        expect(context).to include("Decisions")
        expect(context).to include("PostgreSQL")
      end
    end

    context "with convention facts in global store" do
      before do
        create_fact_with_content(
          manager.global_store,
          "convention",
          "Use 2-space indentation for Ruby files",
          "convention style format Use 2-space indentation for Ruby files",
          scope: "global"
        )
      end

      it "includes conventions in context" do
        context = injector.generate_context
        expect(context).to include("Conventions")
        expect(context).to include("2-space indentation")
      end
    end

    context "with architecture facts" do
      before do
        create_fact_with_content(
          manager.project_store,
          "uses_framework",
          "Rails 7 with Hotwire",
          "uses framework implements architecture Rails 7 with Hotwire"
        )
      end

      it "includes architecture in context" do
        context = injector.generate_context
        expect(context).to include("Architecture")
        expect(context).to include("Rails 7")
      end
    end

    context "with mixed facts across databases" do
      before do
        create_fact_with_content(
          manager.project_store,
          "decision",
          "Use JWT for authentication",
          "decision constraint Use JWT for authentication"
        )
        create_fact_with_content(
          manager.global_store,
          "convention",
          "Prefer explicit returns",
          "convention style format Prefer explicit returns",
          scope: "global"
        )
      end

      it "includes facts from both databases" do
        context = injector.generate_context
        expect(context).to include("Decisions")
        expect(context).to include("JWT")
        expect(context).to include("Conventions")
        expect(context).to include("explicit returns")
      end
    end
  end

  describe "emitted fact tracking" do
    let(:decision_fact_id) do
      create_fact_with_content(
        manager.project_store,
        "decision",
        "Use JWT for authentication",
        "decision constraint Use JWT for authentication"
      )
    end

    let(:convention_fact_id) do
      create_fact_with_content(
        manager.global_store,
        "convention",
        "Prefer explicit returns",
        "convention style format Prefer explicit returns",
        scope: "global"
      )
    end

    it "starts with empty tracking state" do
      expect(injector.emitted_fact_ids).to eq([])
      expect(injector.emitted_subjects).to eq([])
    end

    it "records fact IDs and subjects after generate_context" do
      decision_fact_id
      convention_fact_id
      injector.generate_context

      expect(injector.emitted_fact_ids).to include(decision_fact_id, convention_fact_id)
      expect(injector.emitted_subjects).to include("test-repo")
    end

    it "resets tracking on each generate_context call" do
      decision_fact_id
      injector.generate_context
      first_ids = injector.emitted_fact_ids.dup
      expect(first_ids).not_to be_empty

      injector.generate_context
      expect(injector.emitted_fact_ids.size).to eq(first_ids.size)
    end
  end
end
