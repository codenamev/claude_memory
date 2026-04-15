# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe ClaudeMemory::Commands::RejectCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_db_path) { File.join(tmpdir, ".claude", "memory.sqlite3") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }

  before do
    FileUtils.mkdir_p(File.dirname(project_db_path))
    config = instance_double(
      ClaudeMemory::Configuration,
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_dir: tmpdir,
      claude_config_dir: File.join(tmpdir, ".claude")
    )
    allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)
  end

  after do
    FileUtils.remove_entry(tmpdir)
  end

  def insert_fact(predicate:, object:)
    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    entity_id = store.find_or_create_entity(type: "repo", name: "test")
    fact_id = store.insert_fact(subject_entity_id: entity_id, predicate: predicate, object_literal: object)
    docid = store.facts.where(id: fact_id).get(:docid)
    store.close
    [fact_id, docid]
  end

  it "rejects a fact by integer id" do
    fact_id, _ = insert_fact(predicate: "uses_framework", object: "rails")

    exit_code = command.call([fact_id.to_s])

    expect(exit_code).to eq(0)
    expect(stdout.string).to include("Rejected fact ##{fact_id}")

    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    expect(store.facts.where(id: fact_id).get(:status)).to eq("rejected")
    store.close
  end

  it "rejects a fact by docid" do
    fact_id, docid = insert_fact(predicate: "uses_framework", object: "rails")
    expect(docid).not_to be_nil

    exit_code = command.call([docid])

    expect(exit_code).to eq(0)
    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    expect(store.facts.where(id: fact_id).get(:status)).to eq("rejected")
    store.close
  end

  it "reports conflicts resolved when provided" do
    fact_id, _ = insert_fact(predicate: "uses_framework", object: "rails")
    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    other = store.insert_fact(
      subject_entity_id: store.find_or_create_entity(type: "repo", name: "test"),
      predicate: "uses_framework",
      object_literal: "sinatra"
    )
    store.insert_conflict(fact_a_id: fact_id, fact_b_id: other)
    store.close

    command.call([fact_id.to_s, "--reason", "hallucinated"])

    expect(stdout.string).to include("Resolved 1 open conflict")
  end

  it "returns 1 when the fact is missing" do
    insert_fact(predicate: "uses_framework", object: "rails")

    exit_code = command.call(["999999"])

    expect(exit_code).to eq(1)
    expect(stderr.string).to include("not found")
  end

  it "returns 1 when no argument is provided" do
    insert_fact(predicate: "uses_framework", object: "rails")

    exit_code = command.call([])

    expect(exit_code).to eq(1)
    expect(stderr.string).to include("Usage")
  end
end
