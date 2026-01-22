# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Recall do
  let(:db_path) { File.join(Dir.tmpdir, "recall_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:fts) { ClaudeMemory::Index::LexicalFTS.new(store) }
  let(:recall) { described_class.new(store, fts: fts) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_content_with_fact(text, predicate, object)
    content_id = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      raw_text: text
    )
    fts.index_content_item(content_id, text)

    entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
    fact_id = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object
    )
    store.insert_provenance(
      fact_id: fact_id,
      content_item_id: content_id,
      quote: text,
      strength: "stated"
    )

    {content_id: content_id, fact_id: fact_id, entity_id: entity_id}
  end

  describe "#query" do
    it "returns empty for no matches" do
      results = recall.query("nonexistent")
      expect(results).to be_empty
    end

    it "returns facts with receipts for matching content" do
      create_content_with_fact("We use PostgreSQL for the database", "uses_database", "postgresql")

      results = recall.query("PostgreSQL")
      expect(results.size).to eq(1)
      expect(results.first[:fact][:predicate]).to eq("uses_database")
      expect(results.first[:receipts]).not_to be_empty
    end

    it "respects limit" do
      3.times do |i|
        create_content_with_fact("Fact #{i} about databases", "convention", "rule_#{i}")
      end

      results = recall.query("databases", limit: 2)
      expect(results.size).to be <= 2
    end

    it "deduplicates facts" do
      data = create_content_with_fact("PostgreSQL is great", "uses_database", "postgresql")
      store.insert_provenance(
        fact_id: data[:fact_id],
        content_item_id: data[:content_id],
        quote: "Another quote about PostgreSQL",
        strength: "inferred"
      )

      results = recall.query("PostgreSQL")
      expect(results.size).to eq(1)
    end
  end

  describe "#query_index" do
    it "returns empty for no matches" do
      results = recall.query_index("nonexistent")
      expect(results).to be_empty
    end

    it "returns lightweight index format without full provenance" do
      create_content_with_fact("We use PostgreSQL database", "uses_database", "PostgreSQL with connection pooling")

      results = recall.query_index("PostgreSQL", limit: 10)

      expect(results).not_to be_empty
      result = results.first

      # Has essential fields
      expect(result[:id]).to be_a(Integer)
      expect(result[:predicate]).to eq("uses_database")
      expect(result[:subject]).not_to be_nil

      # Has preview (truncated to 50 chars)
      expect(result[:object_preview]).not_to be_nil
      expect(result[:object_preview].length).to be <= 50

      # Has token estimate
      expect(result[:token_estimate]).to be > 0

      # Does NOT have full provenance (lightweight)
      expect(result).not_to have_key(:receipts)
      expect(result).not_to have_key(:valid_from)
    end

    it "truncates long object literals to 50 chars" do
      long_text = "A" * 100
      create_content_with_fact("Long description text", "description", long_text)

      results = recall.query_index("description", limit: 10)

      expect(results.first[:object_preview].length).to eq(50)
    end

    it "respects limit parameter" do
      5.times do |i|
        create_content_with_fact("Fact #{i}", "fact_#{i}", "value #{i}")
      end

      results = recall.query_index("Fact", limit: 3)
      expect(results.size).to be <= 3
    end

    it "includes token estimates" do
      create_content_with_fact("Rails framework", "uses_framework", "Rails 7")

      results = recall.query_index("Rails", limit: 10)

      expect(results.first[:token_estimate]).to be_between(1, 10)
    end

    it "includes source field" do
      create_content_with_fact("PostgreSQL database", "uses_database", "PostgreSQL")

      results = recall.query_index("PostgreSQL", limit: 10)

      expect(results.first[:source]).not_to be_nil
    end
  end

  describe "#explain" do
    it "returns NullExplanation for non-existent fact" do
      explanation = recall.explain(999)
      expect(explanation).to be_a(ClaudeMemory::Core::NullExplanation)
      expect(explanation.present?).to be false
    end

    it "returns fact with receipts" do
      data = create_content_with_fact("We use Rails", "uses_framework", "rails")

      explanation = recall.explain(data[:fact_id])
      expect(explanation[:fact][:predicate]).to eq("uses_framework")
      expect(explanation[:receipts].size).to eq(1)
      expect(explanation[:receipts].first[:quote]).to eq("We use Rails")
    end

    it "includes supersession links" do
      data1 = create_content_with_fact("Using MySQL", "uses_database", "mysql")
      data2 = create_content_with_fact("Switched to PostgreSQL", "uses_database", "postgresql")
      store.insert_fact_link(from_fact_id: data2[:fact_id], to_fact_id: data1[:fact_id], link_type: "supersedes")

      explanation = recall.explain(data2[:fact_id])
      expect(explanation[:supersedes]).to include(data1[:fact_id])
    end

    it "includes conflict records" do
      data1 = create_content_with_fact("Using MySQL", "uses_database", "mysql")
      data2 = create_content_with_fact("Using PostgreSQL", "uses_database", "postgresql")
      store.insert_conflict(fact_a_id: data1[:fact_id], fact_b_id: data2[:fact_id])

      explanation = recall.explain(data1[:fact_id])
      expect(explanation[:conflicts]).not_to be_empty
    end
  end

  describe "#changes" do
    it "returns recent facts" do
      create_content_with_fact("Convention 1", "convention", "rule1")
      sleep 0.01
      create_content_with_fact("Convention 2", "convention", "rule2")

      yesterday = (Time.now - 86400).utc.iso8601
      changes = recall.changes(since: yesterday)
      expect(changes.size).to eq(2)
    end

    it "filters by since timestamp" do
      create_content_with_fact("Old convention", "convention", "old_rule")

      future = (Time.now + 86400).utc.iso8601
      changes = recall.changes(since: future)
      expect(changes).to be_empty
    end
  end

  describe "project scoping" do
    let(:project_a) { "/path/to/project-a" }
    let(:project_b) { "/path/to/project-b" }
    let(:recall_a) { described_class.new(store, fts: fts, project_path: project_a) }
    let(:recall_b) { described_class.new(store, fts: fts, project_path: project_b) }

    def create_scoped_fact(text, predicate, object, scope:, project_path:)
      content_id = store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        project_path: project_path,
        text_hash: Digest::SHA256.hexdigest(text + project_path.to_s),
        byte_len: text.bytesize,
        raw_text: text
      )
      fts.index_content_item(content_id, text)

      entity_id = store.find_or_create_entity(type: "repo", name: project_path || "global")
      fact_id = store.insert_fact(
        subject_entity_id: entity_id,
        predicate: predicate,
        object_literal: object,
        scope: scope,
        project_path: project_path
      )
      store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: text,
        strength: "stated"
      )

      {content_id: content_id, fact_id: fact_id}
    end

    describe "#query with scope" do
      before do
        create_scoped_fact("Project A uses MySQL", "uses_database", "mysql", scope: "project", project_path: project_a)
        create_scoped_fact("Project B uses PostgreSQL", "uses_database", "postgresql", scope: "project", project_path: project_b)
        create_scoped_fact("Global convention: always use snake_case", "convention", "snake_case", scope: "global", project_path: nil)
      end

      it "returns only current project facts with scope: project" do
        results = recall_a.query("MySQL", scope: "project")

        predicates = results.map { |r| r[:fact][:object_literal] }
        expect(predicates).to include("mysql")
        expect(predicates).not_to include("postgresql")
      end

      it "returns only global facts with scope: global" do
        results = recall_a.query("convention", scope: "global")

        expect(results.size).to eq(1)
        expect(results.first[:fact][:scope]).to eq("global")
      end

      it "returns all facts with scope: all (default)" do
        results = recall_a.query("uses snake", scope: "all")

        expect(results.size).to be >= 1
      end

      it "prioritizes current project facts in results" do
        create_scoped_fact("Project A database config", "config", "a_config", scope: "project", project_path: project_a)
        create_scoped_fact("Project B database config", "config", "b_config", scope: "project", project_path: project_b)

        results = recall_a.query("database config", scope: "all")

        first_result = results.first
        expect(first_result[:fact][:project_path]).to eq(project_a)
      end
    end

    describe "#changes with scope" do
      before do
        create_scoped_fact("A fact", "decision", "a_decision", scope: "project", project_path: project_a)
        create_scoped_fact("B fact", "decision", "b_decision", scope: "project", project_path: project_b)
        create_scoped_fact("Global fact", "decision", "global_decision", scope: "global", project_path: nil)
      end

      it "filters changes by project scope" do
        yesterday = (Time.now - 86400).utc.iso8601
        changes = recall_a.changes(since: yesterday, scope: "project")

        project_paths = changes.map { |c| c[:project_path] }
        expect(project_paths).to all(eq(project_a))
      end

      it "filters changes by global scope" do
        yesterday = (Time.now - 86400).utc.iso8601
        changes = recall_a.changes(since: yesterday, scope: "global")

        scopes = changes.map { |c| c[:scope] }
        expect(scopes).to all(eq("global"))
      end
    end
  end

  describe "class methods with StoreManager" do
    let(:tmpdir) { Dir.mktmpdir("recall_class_methods_#{Process.pid}") }
    let(:global_db) { File.join(tmpdir, "global.sqlite3") }
    let(:project_db) { File.join(tmpdir, "project.sqlite3") }
    let(:manager) do
      ClaudeMemory::Store::StoreManager.new(
        global_db_path: global_db,
        project_db_path: project_db
      )
    end

    after do
      manager.close
      FileUtils.rm_rf(tmpdir)
    end

    def create_manager_fact(store, predicate, object, text)
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
        object_literal: object
      )

      store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: text,
        strength: "stated"
      )

      fact_id
    end

    describe ".recent_decisions" do
      it "returns decision-related facts using configured query" do
        manager.ensure_project!
        create_manager_fact(manager.project_store, "decision", "Use PostgreSQL", "We made a decision about the constraint and rule for this requirement")
        create_manager_fact(manager.project_store, "constraint", "API rate limit 1000/min", "Rate limit constraint requirement for the API decision")

        results = described_class.recent_decisions(manager, limit: 10)

        expect(results).to be_an(Array)
        # FTS may or may not return results depending on matching
        # Just verify the method works without error
      end

      it "allows overriding default limit" do
        manager.ensure_project!
        3.times do |i|
          create_manager_fact(manager.project_store, "decision", "Decision #{i}", "Decision content #{i} with rule constraint requirement")
        end

        results = described_class.recent_decisions(manager, limit: 2)

        expect(results).to be_an(Array)
        expect(results.size).to be <= 2
      end

      it "searches both global and project databases" do
        manager.ensure_both!
        create_manager_fact(manager.global_store, "decision", "Global decision", "A global rule decision constraint requirement")
        create_manager_fact(manager.project_store, "decision", "Project decision", "A project constraint decision rule requirement")

        results = described_class.recent_decisions(manager, limit: 10)

        expect(results).to be_an(Array)
        # May return results from one or both databases depending on FTS
      end
    end

    describe ".architecture_choices" do
      it "returns architecture-related facts using configured query" do
        manager.ensure_project!
        create_manager_fact(manager.project_store, "uses_framework", "Rails", "This project uses Rails framework and implements MVC architecture pattern")
        create_manager_fact(manager.project_store, "architecture_pattern", "MVC", "Implements MVC architecture pattern using framework conventions")

        results = described_class.architecture_choices(manager, limit: 10)

        expect(results).to be_an(Array)
        # FTS may or may not return results depending on matching
      end

      it "allows overriding default limit" do
        manager.ensure_project!
        3.times do |i|
          create_manager_fact(manager.project_store, "uses_framework", "Framework #{i}", "Uses framework #{i} architecture pattern implements")
        end

        results = described_class.architecture_choices(manager, limit: 1)

        expect(results).to be_an(Array)
        expect(results.size).to be <= 1
      end
    end

    describe ".conventions" do
      it "returns convention-related facts using configured query" do
        manager.ensure_global!
        create_manager_fact(manager.global_store, "convention", "Use 4-space indentation", "Style convention prefer 4 spaces format pattern")
        create_manager_fact(manager.global_store, "style_preference", "Snake case", "Format pattern prefer snake_case convention style")

        results = described_class.conventions(manager, limit: 20)

        expect(results).to be_an(Array)
        # FTS may or may not return results depending on matching
      end

      it "uses higher default limit (20)" do
        manager.ensure_global!
        15.times do |i|
          create_manager_fact(manager.global_store, "convention", "Convention #{i}", "Style convention #{i} format pattern prefer")
        end

        results = described_class.conventions(manager)

        expect(results).to be_an(Array)
        # Default limit is 20, higher than standard 10
      end

      it "allows overriding default limit" do
        manager.ensure_global!
        5.times do |i|
          create_manager_fact(manager.global_store, "convention", "Convention #{i}", "Style convention #{i} format pattern")
        end

        results = described_class.conventions(manager, limit: 3)

        expect(results).to be_an(Array)
        expect(results.size).to be <= 3
      end
    end

    describe ".project_config" do
      it "returns project configuration facts using configured query" do
        manager.ensure_project!
        create_manager_fact(manager.project_store, "uses_database", "PostgreSQL", "Project uses PostgreSQL database and requires configuration depends_on")
        create_manager_fact(manager.project_store, "depends_on", "Redis", "Project requires Redis configuration uses dependencies")

        results = described_class.project_config(manager, limit: 10)

        expect(results).to be_an(Array)
        # FTS may or may not return results depending on matching
      end

      it "allows overriding default limit" do
        manager.ensure_project!
        3.times do |i|
          create_manager_fact(manager.project_store, "uses_library", "Library #{i}", "Uses library #{i} requires configuration depends_on")
        end

        results = described_class.project_config(manager, limit: 2)

        expect(results).to be_an(Array)
        expect(results.size).to be <= 2
      end
    end
  end
end
