# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe ClaudeMemory::Commands::Checks::FtsRankCheck do
  let(:db_path) { File.join(Dir.tmpdir, "fts_rank_check_#{Process.pid}.sqlite3") }

  after { FileUtils.rm_f(db_path) }

  def seed_indexed_content
    store = ClaudeMemory::Store::SQLiteStore.new(db_path)
    text = "the project uses sqlite for storage"
    id = store.upsert_content_item(
      source: "claude_code", session_id: "s",
      text_hash: Digest::SHA256.hexdigest(text), byte_len: text.bytesize, raw_text: text
    )
    ClaudeMemory::Index::LexicalFTS.new(store).index_content_item(id, text)
    store.close
  end

  it "reports healthy when the FTS5 rank path works" do
    seed_indexed_content
    result = described_class.new(db_path, "project").call

    expect(result[:status]).to eq(:ok)
    expect(result[:label]).to eq("project_fts")
    expect(result[:message]).to match(/healthy/)
  end

  it "reports an error pointing at compact when the rank index is corrupt" do
    seed_indexed_content
    allow_any_instance_of(ClaudeMemory::Index::LexicalFTS).to receive(:search)
      .and_raise(ClaudeMemory::Index::LexicalFTS::CorruptRankIndexError, "corrupt; run compact")

    result = described_class.new(db_path, "project").call

    expect(result[:status]).to eq(:error)
    expect(result[:message]).to match(/compact/)
  end

  it "skips (ok) when the database does not exist" do
    result = described_class.new("/no/such/db.sqlite3", "global").call

    expect(result[:status]).to eq(:ok)
    expect(result[:message]).to match(/no database/)
  end
end
