# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Commands::ExportCommand do
  let(:tmpdir) { Dir.mktmpdir("export_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path
    )
  end

  before do
    manager.ensure_both!

    allow(ClaudeMemory::Store::StoreManager).to receive(:new).and_return(manager)
  end

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  def create_fact(store, predicate, object, scope: "project")
    entity_id = store.find_or_create_entity(type: "repo", name: "test-repo")
    fact_id = store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      scope: scope
    )

    content_id = store.upsert_content_item(
      source: "test",
      session_id: "sess-1",
      text_hash: Digest::SHA256.hexdigest(object),
      byte_len: object.bytesize,
      raw_text: object
    )
    store.insert_provenance(
      fact_id: fact_id,
      content_item_id: content_id,
      quote: object,
      strength: "stated"
    )

    fact_id
  end

  describe "exporting facts" do
    it "exports project facts to stdout as JSON" do
      create_fact(manager.project_store, "convention", "use tabs")

      exit_code = command.call(["--scope", "project"])

      expect(exit_code).to eq(0)
      data = JSON.parse(stdout.string)
      expect(data["facts"].size).to eq(1)
      expect(data["facts"].first["predicate"]).to eq("convention")
      expect(data["facts"].first["object"]).to eq("use tabs")
      expect(data["facts"].first["source"]).to eq("project")
    end

    it "exports global facts" do
      create_fact(manager.global_store, "convention", "prefer spaces", scope: "global")

      exit_code = command.call(["--scope", "global"])

      expect(exit_code).to eq(0)
      data = JSON.parse(stdout.string)
      expect(data["facts"].size).to eq(1)
      expect(data["facts"].first["source"]).to eq("global")
    end

    it "exports all scopes together" do
      create_fact(manager.project_store, "convention", "use tabs")
      create_fact(manager.global_store, "convention", "prefer spaces", scope: "global")

      exit_code = command.call(["--scope", "all"])

      expect(exit_code).to eq(0)
      data = JSON.parse(stdout.string)
      expect(data["facts"].size).to eq(2)
      sources = data["facts"].map { |f| f["source"] }
      expect(sources).to include("global", "project")
    end

    it "includes provenance receipts" do
      create_fact(manager.project_store, "convention", "use tabs")

      command.call(["--scope", "project"])

      data = JSON.parse(stdout.string)
      receipts = data["facts"].first["receipts"]
      expect(receipts.size).to eq(1)
      expect(receipts.first["quote"]).to eq("use tabs")
      expect(receipts.first["strength"]).to eq("stated")
    end

    it "includes entities" do
      create_fact(manager.project_store, "convention", "use tabs")

      command.call(["--scope", "project"])

      data = JSON.parse(stdout.string)
      expect(data["entities"].size).to eq(1)
      expect(data["entities"].first["name"]).to eq("test-repo")
      expect(data["entities"].first["type"]).to eq("repo")
    end

    it "includes version and timestamp metadata" do
      command.call(["--scope", "project"])

      data = JSON.parse(stdout.string)
      expect(data["version"]).to eq(ClaudeMemory::VERSION)
      expect(data["exported_at"]).to match(/\d{4}-\d{2}-\d{2}T/)
      expect(data["scope"]).to eq("project")
    end
  end

  describe "--status flag" do
    it "exports only active facts by default" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
      manager.project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "active fact",
        status: "active"
      )
      manager.project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "superseded fact",
        status: "superseded"
      )

      command.call(["--scope", "project"])

      data = JSON.parse(stdout.string)
      expect(data["facts"].size).to eq(1)
      expect(data["facts"].first["object"]).to eq("active fact")
    end

    it "exports all facts with --status all" do
      entity_id = manager.project_store.find_or_create_entity(type: "repo", name: "test")
      manager.project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "active fact",
        status: "active"
      )
      manager.project_store.insert_fact(
        subject_entity_id: entity_id,
        predicate: "convention",
        object_literal: "superseded fact",
        status: "superseded"
      )

      command.call(["--scope", "project", "--status", "all"])

      data = JSON.parse(stdout.string)
      expect(data["facts"].size).to eq(2)
    end
  end

  describe "--output flag" do
    it "writes to file instead of stdout" do
      create_fact(manager.project_store, "convention", "use tabs")
      output_path = File.join(tmpdir, "export.json")

      exit_code = command.call(["--scope", "project", "--output", output_path])

      expect(exit_code).to eq(0)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include("Exported 1 facts")

      data = JSON.parse(File.read(output_path))
      expect(data["facts"].size).to eq(1)
    end
  end

  describe "--pretty flag" do
    it "pretty-prints JSON output" do
      create_fact(manager.project_store, "convention", "use tabs")

      command.call(["--scope", "project", "--pretty"])

      expect(stdout.string).to include("\n")
      expect(stdout.string).to match(/^\s+"predicate"/)
    end
  end

  describe "empty databases" do
    it "exports empty arrays when no facts exist" do
      command.call(["--scope", "project"])

      data = JSON.parse(stdout.string)
      expect(data["facts"]).to eq([])
      expect(data["entities"]).to eq([])
    end
  end
end
