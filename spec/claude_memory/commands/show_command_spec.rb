# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "digest"

RSpec.describe ClaudeMemory::Commands::ShowCommand do
  let(:tmpdir) { Dir.mktmpdir("show_test_#{Process.pid}") }
  let(:global_db_path) { File.join(tmpdir, "global.sqlite3") }
  let(:project_db_path) { File.join(tmpdir, "project.sqlite3") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: global_db_path,
      project_db_path: project_db_path,
      project_path: tmpdir
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

  def seed_indexed_fact(store, predicate:, object:, scope: "project")
    text = "#{predicate} #{object}"
    content_id = store.upsert_content_item(
      source: "test", session_id: "sess-1",
      text_hash: Digest::SHA256.hexdigest(text + rand.to_s),
      byte_len: text.bytesize, raw_text: text
    )
    ClaudeMemory::Index::LexicalFTS.new(store).index_content_item(content_id, text)
    entity_id = store.find_or_create_entity(type: "repo", name: "app")
    fact_id = store.insert_fact(
      subject_entity_id: entity_id, predicate: predicate,
      object_literal: object, status: "active",
      scope: scope, project_path: (scope == "project") ? tmpdir : nil
    )
    store.insert_provenance(
      fact_id: fact_id, content_item_id: content_id,
      quote: text, strength: "stated"
    )
    fact_id
  end

  describe "#call" do
    it "prints the empty-state message when there are no facts" do
      exit_code = command.call([])

      expect(exit_code).to eq(0)
      out = stdout.string
      expect(out).to include("Memory snapshot")
      expect(out).to include("would be injected at next SessionStart")
      expect(out).to include("_Memory has no facts to inject yet._")
    end

    it "prints the would-be-injected markdown when facts exist" do
      seed_indexed_fact(manager.project_store,
        predicate: "decision", object: "Use Redis for caching")
      seed_indexed_fact(manager.project_store,
        predicate: "convention", object: "Prefer do...end blocks")

      exit_code = command.call([])

      expect(exit_code).to eq(0)
      out = stdout.string
      expect(out).to include("Memory snapshot")
      expect(out).to include("## Decisions")
      expect(out).to include("Redis")
      expect(out).to include("## Conventions")
      expect(out).to include("do...end")
    end

    it "prints a footer with fact count and token estimate when facts exist" do
      seed_indexed_fact(manager.project_store,
        predicate: "decision", object: "Use Redis for caching")

      command.call([])

      out = stdout.string
      expect(out).to match(/\d+ facts? • ~\d+ tokens? • \d+ chars/)
    end

    it "honors --source flag and labels the header accordingly" do
      seed_indexed_fact(manager.project_store,
        predicate: "decision", object: "Use Redis for caching")

      exit_code = command.call(["--source", "resume"])

      expect(exit_code).to eq(0)
      expect(stdout.string).to include("(source=resume)")
    end

    it "suppresses the pending-knowledge dump by default" do
      # Seed an undistilled content_item that would normally trigger
      # the "Pending Knowledge Extraction" section on a fresh session.
      text = "raw transcript dump that should not appear by default " * 20
      manager.project_store.upsert_content_item(
        source: "claude_code", session_id: "sess-x",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize, raw_text: text
      )

      command.call([])

      expect(stdout.string).not_to include("Pending Knowledge Extraction")
    end

    it "includes the pending-knowledge dump when --pending is passed" do
      text = "raw transcript dump that should appear with --pending " * 20
      manager.project_store.upsert_content_item(
        source: "claude_code", session_id: "sess-x",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize, raw_text: text
      )

      command.call(["--pending"])

      expect(stdout.string).to include("Pending Knowledge Extraction")
    end
  end

  describe "registry integration" do
    it "is registered as 'show'" do
      expect(ClaudeMemory::Commands::Registry.find("show")).to eq(described_class)
    end

    it "appears in the descriptions hash" do
      expect(ClaudeMemory::Commands::Registry.descriptions).to include("show" => an_instance_of(String))
    end
  end
end
