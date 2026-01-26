# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Commands::IndexCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }
  let(:global_db_path) { File.join(Dir.tmpdir, "index_test_global_#{Process.pid}.sqlite3") }
  let(:project_db_path) { File.join(Dir.tmpdir, "index_test_project_#{Process.pid}.sqlite3") }

  before do
    # Set up test databases
    allow(ClaudeMemory::Configuration).to receive(:global_db_path).and_return(global_db_path)
    allow(ClaudeMemory::Configuration).to receive(:project_db_path).and_return(project_db_path)

    # Create global database with facts
    global_store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
    entity_id = global_store.entities.insert(
      type: "framework",
      canonical_name: "React",
      slug: "react",
      created_at: Time.now.utc.iso8601
    )
    global_store.facts.insert(
      subject_entity_id: entity_id,
      predicate: "is_popular",
      object_literal: "true",
      created_at: Time.now.utc.iso8601,
      scope: "global"
    )
    global_store.close

    # Create project database with facts
    project_store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
    entity_id = project_store.entities.insert(
      type: "database",
      canonical_name: "PostgreSQL",
      slug: "postgresql",
      created_at: Time.now.utc.iso8601
    )
    project_store.facts.insert(
      subject_entity_id: entity_id,
      predicate: "uses_version",
      object_literal: "15",
      created_at: Time.now.utc.iso8601,
      scope: "project"
    )
    project_store.close
  end

  after do
    FileUtils.rm_f(global_db_path)
    FileUtils.rm_f(project_db_path)
  end

  describe "#call" do
    it "indexes facts in both databases by default" do
      exit_code = command.call([])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Global database: Indexing 1 facts")
      expect(output).to include("Project database: Indexing 1 facts")
      expect(output).to include("Done!")

      # Verify embeddings were created
      global_store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      fact = global_store.facts.first
      expect(fact[:embedding_json]).not_to be_nil
      embedding = JSON.parse(fact[:embedding_json])
      expect(embedding).to be_an(Array)
      expect(embedding.size).to eq(384)
      global_store.close

      project_store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      fact = project_store.facts.first
      expect(fact[:embedding_json]).not_to be_nil
      project_store.close
    end

    it "indexes only global database with --scope=global" do
      exit_code = command.call(["--scope=global"])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Global database: Indexing 1 facts")
      expect(output).not_to include("Project database")
    end

    it "indexes only project database with --scope=project" do
      exit_code = command.call(["--scope=project"])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Project database: Indexing 1 facts")
      expect(output).not_to include("Global database")
    end

    it "skips facts that already have embeddings" do
      # Index once
      command.call([])
      stdout.truncate(0)
      stdout.rewind

      # Try to index again
      exit_code = command.call([])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Global database: All facts already indexed")
      expect(output).to include("Project database: All facts already indexed")
    end

    it "re-indexes with --force flag" do
      # Index once
      command.call([])
      stdout.truncate(0)
      stdout.rewind

      # Re-index with --force
      exit_code = command.call(["--force"])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Global database: Indexing 1 facts")
      expect(output).to include("Project database: Indexing 1 facts")
    end

    it "uses custom batch size" do
      # Create multiple facts
      project_store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      entity_id = project_store.entities.where(canonical_name: "PostgreSQL").first[:id]
      5.times do |i|
        project_store.facts.insert(
          subject_entity_id: entity_id,
          predicate: "has_feature",
          object_literal: "feature_#{i}",
          created_at: Time.now.utc.iso8601,
          scope: "project"
        )
      end
      project_store.close

      exit_code = command.call(["--scope=project", "--batch-size=2"])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Indexing 6 facts")
      expect(output).to include("Processed 2 facts")
      expect(output).to include("Processed 4 facts")
      expect(output).to include("Processed 6 facts")
    end

    it "returns error for invalid scope" do
      exit_code = command.call(["--scope=invalid"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to include("Invalid scope: invalid")
    end

    it "skips missing databases" do
      FileUtils.rm_f(project_db_path)

      exit_code = command.call([])

      expect(exit_code).to eq(0)
      output = stdout.string
      expect(output).to include("Project database not found, skipping")
      expect(output).to include("Global database: Indexing 1 facts")
    end

    it "builds rich fact text from entities" do
      exit_code = command.call(["--scope=global"])

      expect(exit_code).to eq(0)

      # Verify the embedding was generated from proper text
      global_store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      fact = global_store.facts.first
      embedding_json = fact[:embedding_json]
      expect(embedding_json).not_to be_nil

      # The text should be "React is_popular true"
      # We can't verify the exact text, but we can verify the embedding exists
      embedding = JSON.parse(embedding_json)
      expect(embedding).to be_an(Array)
      expect(embedding.all? { |v| v.is_a?(Float) }).to be true
      global_store.close
    end
  end
end
