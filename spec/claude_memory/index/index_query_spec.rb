# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Index::IndexQuery do
  let(:db_path) { File.join(Dir.tmpdir, "index_query_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:fts) { ClaudeMemory::Index::LexicalFTS.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def create_test_data
    now = Time.now.iso8601

    # Create entities
    entity_id = store.entities.insert(
      type: "repo",
      canonical_name: "test_project",
      slug: "test-project",
      created_at: now
    )

    # Create facts
    fact_id_1 = store.facts.insert(
      subject_entity_id: entity_id,
      predicate: "uses_database",
      object_literal: "PostgreSQL with connection pooling",
      scope: "project",
      confidence: 1.0,
      status: "active",
      created_at: now
    )

    fact_id_2 = store.facts.insert(
      subject_entity_id: entity_id,
      predicate: "uses_framework",
      object_literal: "Rails 7",
      scope: "project",
      confidence: 1.0,
      status: "active",
      created_at: now
    )

    fact_id_3 = store.facts.insert(
      subject_entity_id: entity_id,
      predicate: "architecture",
      object_literal: "Microservices architecture",
      scope: "project",
      confidence: 1.0,
      status: "active",
      created_at: now
    )

    # Create content items
    content_id_1 = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      transcript_path: "/tmp/test.txt",
      text_hash: "hash1",
      byte_len: 100,
      raw_text: "Using PostgreSQL database"
    )

    content_id_2 = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      transcript_path: "/tmp/test.txt",
      text_hash: "hash2",
      byte_len: 100,
      raw_text: "Rails framework"
    )

    content_id_3 = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      transcript_path: "/tmp/test.txt",
      text_hash: "hash3",
      byte_len: 100,
      raw_text: "Microservices architecture design"
    )

    # Create provenance (link facts to content)
    store.provenance.insert(
      fact_id: fact_id_1,
      content_item_id: content_id_1,
      quote: "PostgreSQL",
      strength: "stated"
    )

    store.provenance.insert(
      fact_id: fact_id_2,
      content_item_id: content_id_2,
      quote: "Rails",
      strength: "stated"
    )

    store.provenance.insert(
      fact_id: fact_id_3,
      content_item_id: content_id_3,
      quote: "Microservices",
      strength: "stated"
    )

    # Index content
    fts.index_content_item(content_id_1, "Using PostgreSQL database")
    fts.index_content_item(content_id_2, "Rails framework")
    fts.index_content_item(content_id_3, "Microservices architecture design")

    {
      fact_ids: [fact_id_1, fact_id_2, fact_id_3],
      content_ids: [content_id_1, content_id_2, content_id_3]
    }
  end

  describe "#execute" do
    it "returns lightweight index format with fact previews" do
      data = create_test_data

      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "database",
        limit: 10,
        scope: :project,
        source: :project
      )

      query = described_class.new(store, options)
      results = query.execute

      expect(results).not_to be_empty
      result = results.first

      expect(result[:id]).to eq(data[:fact_ids][0])
      expect(result[:predicate]).to eq("uses_database")
      expect(result[:object_preview]).to eq("PostgreSQL with connection pooling")
      expect(result[:object_preview].length).to be <= 50
      expect(result[:status]).to eq("active")
      expect(result[:scope]).to eq("project")
      expect(result[:confidence]).to eq(1.0)
      expect(result[:token_estimate]).to be > 0
      expect(result[:source]).to eq(:project)
    end

    it "truncates long object literals to 50 chars" do
      now = Time.now.iso8601
      entity_id = store.entities.insert(
        type: "repo",
        canonical_name: "test",
        slug: "test",
        created_at: now
      )

      long_text = "This is a very long description that exceeds fifty characters and should be truncated when returned in the preview format"

      fact_id = store.facts.insert(
        subject_entity_id: entity_id,
        predicate: "description",
        object_literal: long_text,
        scope: "project",
        confidence: 1.0,
        status: "active",
        created_at: now
      )

      content_id = store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        transcript_path: "/tmp/test.txt",
        text_hash: "hash",
        byte_len: long_text.bytesize,
        raw_text: long_text
      )

      store.provenance.insert(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: "long description",
        strength: "stated"
      )

      fts.index_content_item(content_id, long_text)

      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "description",
        limit: 10,
        source: :project
      )

      query = described_class.new(store, options)
      results = query.execute

      expect(results.first[:object_preview].length).to eq(50)
    end

    it "respects query limit" do
      create_test_data

      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "test",
        limit: 2,
        source: :project
      )

      query = described_class.new(store, options)
      results = query.execute

      expect(results.size).to be <= 2
    end

    it "includes subject name from entity" do
      data = create_test_data

      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "database",
        limit: 10,
        source: :project
      )

      query = described_class.new(store, options)
      results = query.execute

      expect(results.first[:subject]).to eq("test_project")
    end

    it "returns empty array when no matches" do
      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "nonexistent",
        limit: 10,
        source: :project
      )

      query = described_class.new(store, options)
      results = query.execute

      expect(results).to eq([])
    end

    it "handles facts without entities (null subject)" do
      now = Time.now.iso8601
      fact_id = store.facts.insert(
        subject_entity_id: nil,
        predicate: "global_setting",
        object_literal: "value",
        scope: "global",
        confidence: 1.0,
        status: "active",
        created_at: now
      )

      content_id = store.upsert_content_item(
        source: "test",
        session_id: "sess-1",
        transcript_path: "/tmp/test.txt",
        text_hash: "hash",
        byte_len: 10,
        raw_text: "setting"
      )

      store.provenance.insert(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: "setting",
        strength: "stated"
      )

      fts.index_content_item(content_id, "setting")

      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "setting",
        limit: 10,
        source: :project
      )

      query = described_class.new(store, options)
      results = query.execute

      expect(results.first[:subject]).to be_nil
    end

    it "makes constant number of queries regardless of result size" do
      # Create many facts with provenance
      now = Time.now.iso8601
      entity_id = store.entities.insert(
        type: "repo",
        canonical_name: "test",
        slug: "test-repo",
        created_at: now
      )

      30.times do |i|
        fact_id = store.facts.insert(
          subject_entity_id: entity_id,
          predicate: "fact_#{i}",
          object_literal: "value #{i}",
          scope: "project",
          confidence: 1.0,
          status: "active",
          created_at: now
        )

        content_id = store.upsert_content_item(
          source: "test",
          session_id: "sess-1",
          transcript_path: "/tmp/test.txt",
          text_hash: "hash#{i}",
          byte_len: 10,
          raw_text: "test content #{i}"
        )

        store.provenance.insert(
          fact_id: fact_id,
          content_item_id: content_id,
          quote: "test",
          strength: "stated"
        )

        fts.index_content_item(content_id, "test content #{i}")
      end

      options = ClaudeMemory::Index::QueryOptions.new(
        query_text: "test",
        limit: 30,
        source: :project
      )

      query = described_class.new(store, options)

      # Count queries by enabling SQL logging
      query_count = 0
      original_loggers = store.db.loggers
      logger = Object.new
      def logger.info(msg)
        # Count SELECT queries only
        @count ||= 0
        @count += 1 if msg.is_a?(String) && msg.upcase.include?("SELECT")
      end

      def logger.count
        @count || 0
      end

      store.db.loggers = [logger]
      results = query.execute
      store.db.loggers = original_loggers

      # Should be approximately 3 queries:
      # 1. FTS search for content IDs
      # 2. Batch fetch provenance
      # 3. Batch fetch facts with entities
      expect(logger.count).to be <= 5 # Allow some buffer for FTS internals
      expect(results.size).to be > 0
    end
  end
end
