# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Abstention eval, slice 1: recall-level only. A fact changes (v1 -> v2) and
# we score what recall hands the model. The failure we care about is
# stale-confident: v1 surfaced as current with nothing marking it old.
RSpec.describe "Recall abstention: superseded facts" do
  let(:test_dir) { File.join(Dir.tmpdir, "recall_abstention_test_#{Process.pid}") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: File.join(test_dir, "global.sqlite3"),
      project_db_path: File.join(test_dir, "project.sqlite3")
    )
  end
  let(:store) { manager.project_store }
  let(:resolver) { ClaudeMemory::Resolve::Resolver.new(store) }
  let(:recall) { ClaudeMemory::Recall.new(manager) }

  before do
    FileUtils.mkdir_p(test_dir)
    manager.ensure_both!
  end

  after do
    manager.close
    FileUtils.rm_rf(test_dir)
  end

  # Recall finds facts through FTS on content + provenance, so each fact
  # needs a source content item or it is invisible to recall entirely.
  def remember(object, supersedes: false)
    text = "The repo deploys with #{object}"
    content_id = store.upsert_content_item(
      source: "test",
      session_id: "sess-#{object}",
      text_hash: Digest::SHA256.hexdigest(text),
      byte_len: text.bytesize,
      raw_text: text
    )
    ClaudeMemory::Index::LexicalFTS.new(store).index_content_item(content_id, text)
    resolver.apply(
      ClaudeMemory::Distill::Extraction.new(
        facts: [{subject: "repo", predicate: "deployment_platform", object: object, strength: "stated", supersedes: supersedes}]
      ),
      content_item_id: content_id,
      project_path: test_dir
    )
  end

  def objects_for(query)
    recall.query(query, scope: "project").map { |r| r.dig(:fact, :object_literal) }
  end

  # Stale-confident = v1 comes back still marked active. Recall may surface
  # a superseded fact (that's history), but never unmarked as current.
  def v1_status(query)
    v1 = recall.query(query, scope: "project").find { |r| r.dig(:fact, :object_literal) == "capistrano" }
    v1&.dig(:fact, :status)
  end

  context "(a) supersession recorded" do
    before do
      remember("capistrano")
      remember("kamal", supersedes: true)
    end

    it "returns v2 as active and never returns v1 as active" do
      v2 = recall.query("kamal", scope: "project").find { |r| r.dig(:fact, :object_literal) == "kamal" }
      expect(v2.dig(:fact, :status)).to eq("active")
      expect(v1_status("capistrano")).not_to eq("active")
    end

    it "links v2 back to v1 so the change is explainable" do
      v2 = recall.query("kamal", scope: "project").first
      explanation = recall.explain(v2[:fact][:id], scope: "project")
      expect(explanation[:supersedes]).not_to be_empty
    end
  end

  context "(b) v2 stored without a supersession signal" do
    before do
      remember("capistrano")
      remember("kamal")
    end

    # Exclusive single-cardinality slot: a stated v2 auto-supersedes v1
    # without opening a conflict, so the bar is the same as (a).
    it "does not leave v1 marked active" do
      expect(v1_status("deploys with capistrano")).not_to eq("active")
    end
  end
end
