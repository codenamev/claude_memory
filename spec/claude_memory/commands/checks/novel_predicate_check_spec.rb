# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::Checks::NovelPredicateCheck do
  let(:db_path) { File.join(Dir.tmpdir, "novel_predicate_check_#{Process.pid}.sqlite3") }

  after { FileUtils.rm_f(db_path) }

  def seed_facts(predicate, *values)
    store = ClaudeMemory::Store::SQLiteStore.new(db_path)
    subject = store.find_or_create_entity(type: "repo", name: "app")
    values.each { |v| store.insert_fact(subject_entity_id: subject, predicate: predicate, object_literal: v) }
    store.close
  end

  it "warns when one subject has multiple active facts on a novel predicate" do
    seed_facts("deploys_with", "heroku", "fly")
    result = described_class.new(db_path, "project").call

    expect(result[:status]).to eq(:warning)
    expect(result[:label]).to eq("project_novel_predicates")
    expect(result[:details][:pairs]).to eq(1)
    expect(result[:details][:examples].first).to match(/deploys_with/)
  end

  it "is ok when a novel predicate has a single active value" do
    seed_facts("deploys_with", "fly")
    expect(described_class.new(db_path, "project").call[:status]).to eq(:ok)
  end

  it "ignores predicates PredicatePolicy knows" do
    seed_facts("uses_language", "ruby", "sql")
    expect(described_class.new(db_path, "project").call[:status]).to eq(:ok)
  end

  it "skips (ok) when the database does not exist" do
    result = described_class.new("/no/such/db.sqlite3", "global").call

    expect(result[:status]).to eq(:ok)
    expect(result[:message]).to match(/no database/)
  end
end
