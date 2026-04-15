# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe ClaudeMemory::Commands::RestoreCommand do
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

  def seed_multi_framework
    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    repo_id = store.find_or_create_entity(type: "repo", name: "test")
    active = store.insert_fact(subject_entity_id: repo_id, predicate: "uses_framework", object_literal: "Rails 8.1")
    old = store.insert_fact(subject_entity_id: repo_id, predicate: "uses_framework", object_literal: "Tailwind CSS")
    store.facts.where(id: old).update(status: "superseded", valid_to: Time.now.utc.iso8601)
    store.insert_fact_link(from_fact_id: active, to_fact_id: old, link_type: "supersedes")
    store.close
    [active, old]
  end

  it "requires --predicate" do
    exit_code = command.call([])
    expect(exit_code).to eq(1)
    expect(stderr.string).to include("--predicate required")
  end

  it "restores disjoint superseded facts" do
    _, old_id = seed_multi_framework

    exit_code = command.call(["--predicate", "uses_framework"])

    expect(exit_code).to eq(0)
    expect(stdout.string).to include("Restored:          1")
    expect(stdout.string).to include("[restore]")

    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    expect(store.facts.where(id: old_id).get(:status)).to eq("active")
    store.close
  end

  it "supports --dry-run" do
    _, old_id = seed_multi_framework

    command.call(["--predicate", "uses_framework", "--dry-run"])

    expect(stdout.string).to include("DRY RUN")
    store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    expect(store.facts.where(id: old_id).get(:status)).to eq("superseded")
    store.close
  end

  it "refuses to restore a still-single-value predicate" do
    exit_code = command.call(["--predicate", "uses_database"])
    expect(exit_code).to eq(1)
    expect(stderr.string).to include("still classified single-value")
  end
end
