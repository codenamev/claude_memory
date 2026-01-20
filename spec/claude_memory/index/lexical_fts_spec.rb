# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Index::LexicalFTS do
  let(:db_path) { File.join(Dir.tmpdir, "fts_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:fts) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe "#index_content_item" do
    it "indexes a content item" do
      id = store.upsert_content_item(
        source: "claude_code",
        session_id: "sess-1",
        text_hash: "hash1",
        byte_len: 100,
        raw_text: "We decided to use PostgreSQL for the database."
      )

      expect { fts.index_content_item(id, "We decided to use PostgreSQL for the database.") }
        .not_to raise_error
    end
  end

  describe "#search" do
    before do
      [
        {text: "We are using PostgreSQL as our primary database.", hash: "h1"},
        {text: "The authentication system uses JWT tokens.", hash: "h2"},
        {text: "Deploy to AWS using Terraform scripts.", hash: "h3"},
        {text: "PostgreSQL requires proper indexing for performance.", hash: "h4"}
      ].each do |item|
        id = store.upsert_content_item(
          source: "claude_code",
          session_id: "sess-1",
          text_hash: item[:hash],
          byte_len: item[:text].bytesize,
          raw_text: item[:text]
        )
        fts.index_content_item(id, item[:text])
      end
    end

    it "finds content matching query" do
      results = fts.search("PostgreSQL")
      expect(results.size).to eq(2)
    end

    it "returns empty array when no matches" do
      results = fts.search("MongoDB")
      expect(results).to be_empty
    end

    it "respects limit" do
      results = fts.search("PostgreSQL", limit: 1)
      expect(results.size).to eq(1)
    end

    it "returns content_item_ids" do
      results = fts.search("JWT")
      expect(results.first).to be_a(Integer)
    end

    it "handles multi-word queries" do
      results = fts.search("authentication JWT")
      expect(results.size).to eq(1)
    end
  end
end
