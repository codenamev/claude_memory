# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Resolve::Resolver, "observations persistence" do
  let(:db_path) { File.join(Dir.tmpdir, "resolver_obs_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }
  let(:resolver) { described_class.new(store) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  def extraction_with_observations(observations)
    ClaudeMemory::Distill::Extraction.new(observations: observations)
  end

  it "persists observations from the extraction and reports the count" do
    ex = extraction_with_observations([
      {kind: "decision", priority: 1, body: "decided to add an episodic layer"},
      {kind: "preference", priority: 2, body: "prefer do...end blocks"}
    ])

    result = resolver.apply(ex, content_item_id: 42, scope: "project", project_path: "/proj")

    expect(result[:observations_created]).to eq(2)
    rows = store.recent_observations(scope: "project")
    expect(rows.map { |r| r[:body] }).to contain_exactly("decided to add an episodic layer", "prefer do...end blocks")
    expect(rows).to all(include(source_content_item_id: 42, project_path: "/proj"))
  end

  it "applies the resolver scope and clears project_path for global scope" do
    ex = extraction_with_observations([{body: "global note", priority: 3}])

    resolver.apply(ex, content_item_id: 1, scope: "global", project_path: "/ignored")

    row = store.recent_observations(scope: "global").first
    expect(row[:scope]).to eq("global")
    expect(row[:project_path]).to be_nil
  end

  it "does not create observations for an extraction without any (fact behavior unchanged)" do
    ex = ClaudeMemory::Distill::Extraction.new(facts: [])
    result = resolver.apply(ex, content_item_id: 1, scope: "project")

    expect(result[:observations_created]).to eq(0)
    expect(store.recent_observations).to be_empty
  end
end
