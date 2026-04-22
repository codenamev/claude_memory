# frozen_string_literal: true

require "digest"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Dashboard::FactPresenter do
  let(:tmpdir) { Dir.mktmpdir("fact_presenter_test_#{Process.pid}") }
  let(:db_path) { File.join(tmpdir, "memory.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:presenter) { described_class.new(store) }

  before do
    FileUtils.mkdir_p(tmpdir)
  end

  after do
    store.close
    FileUtils.rm_rf(tmpdir)
  end

  def make_fact(object_literal: "PostgreSQL", subject: "test-app", predicate: "uses_database")
    subject_id = store.find_or_create_entity(type: "repo", name: subject)
    fact_id = store.insert_fact(
      subject_entity_id: subject_id,
      predicate: predicate,
      object_literal: object_literal,
      status: "active",
      confidence: 0.9,
      scope: "project"
    )
    store.facts.where(id: fact_id).first
  end

  def make_content_item(text: "some quote")
    store.upsert_content_item(
      source: "test",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      session_id: "sess-1",
      occurred_at: "2026-04-22T10:00:00Z",
      raw_text: text
    )
  end

  describe "#summary" do
    it "returns nil for a nil row" do
      expect(presenter.summary(nil)).to be_nil
    end

    it "shapes a fact row with subject, predicate, object, scope, and timestamps" do
      fact = make_fact

      result = presenter.summary(fact)

      expect(result).to include(
        id: fact[:id],
        docid: fact[:docid],
        subject: "test-app",
        predicate: "uses_database",
        object: "PostgreSQL",
        status: "active",
        confidence: 0.9,
        scope: "project"
      )
      expect(result[:created_at]).to be_a(String)
      expect(result[:created_ago]).to be_a(String)
    end

    it "falls back to 'unknown' when the subject entity can't be resolved" do
      fact = make_fact.merge(subject_entity_id: 999_999)

      result = presenter.summary(fact)

      expect(result[:subject]).to eq("unknown")
    end

    it "prefers object_literal over the object entity's canonical_name" do
      fact = make_fact(object_literal: "my override")

      result = presenter.summary(fact)

      expect(result[:object]).to eq("my override")
    end
  end

  describe "#preview" do
    it "returns nil for a nil row" do
      expect(presenter.preview(nil)).to be_nil
    end

    it "returns a compact shape without timestamps or confidence" do
      fact = make_fact

      result = presenter.preview(fact)

      expect(result.keys).to contain_exactly(:id, :docid, :subject, :predicate, :object, :scope, :status)
    end

    it "truncates long object text with an ellipsis" do
      long_text = "x" * 200
      fact = make_fact(object_literal: long_text)

      result = presenter.preview(fact)

      expect(result[:object]).to end_with("…")
      expect(result[:object].length).to eq(described_class::OBJECT_PREVIEW_CHARS + 1)
    end

    it "does not truncate short object text" do
      fact = make_fact(object_literal: "short")

      result = presenter.preview(fact)

      expect(result[:object]).to eq("short")
    end
  end

  describe "#with_provenance" do
    it "returns nil for a nil row" do
      expect(presenter.with_provenance(nil)).to be_nil
    end

    it "merges a :provenance array with quote, strength, and session context" do
      fact = make_fact
      ci_id = make_content_item(text: "claims PostgreSQL")
      store.insert_provenance(
        fact_id: fact[:id], content_item_id: ci_id,
        quote: "we use PostgreSQL", strength: "stated"
      )

      result = presenter.with_provenance(fact)

      expect(result[:provenance].size).to eq(1)
      prov = result[:provenance].first
      expect(prov).to include(
        quote: "we use PostgreSQL",
        strength: "stated",
        session_id: "sess-1",
        occurred_at: "2026-04-22T10:00:00Z"
      )
    end

    it "handles provenance with nil content_item_id (promoted facts)" do
      fact = make_fact
      store.insert_provenance(fact_id: fact[:id], content_item_id: nil, strength: "inferred")

      result = presenter.with_provenance(fact)

      prov = result[:provenance].first
      expect(prov[:content_item_id]).to be_nil
      expect(prov[:session_id]).to be_nil
      expect(prov[:occurred_at]).to be_nil
    end
  end

  describe "#list_summary" do
    it "returns an empty array for empty input" do
      expect(presenter.list_summary([])).to eq([])
    end

    it "serializes multiple rows, resolving each subject from the batched lookup" do
      fact1 = make_fact(subject: "app-one", object_literal: "A")
      fact2 = make_fact(subject: "app-two", object_literal: "B")
      fact3 = make_fact(subject: "app-one", object_literal: "C")

      results = presenter.list_summary([fact1, fact2, fact3])

      expect(results.map { |r| r[:object] }).to eq(%w[A B C])
      expect(results.map { |r| r[:subject] }).to eq(%w[app-one app-two app-one])
    end

    it "handles rows with nil entity ids without raising" do
      fact = make_fact.merge(subject_entity_id: nil, object_entity_id: nil)

      results = presenter.list_summary([fact])

      expect(results.first[:subject]).to eq("unknown")
    end
  end
end
