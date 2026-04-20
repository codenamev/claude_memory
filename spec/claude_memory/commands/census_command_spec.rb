# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

RSpec.describe ClaudeMemory::Commands::CensusCommand do
  let(:tmpdir) { Dir.mktmpdir("census_test_#{Process.pid}") }
  let(:root) { File.join(tmpdir, "src") }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:command) { described_class.new(stdout: stdout, stderr: stderr) }

  after { FileUtils.rm_rf(tmpdir) }

  def make_project_db(project_name, &block)
    project_root = File.join(root, project_name)
    FileUtils.mkdir_p(File.join(project_root, ".claude"))
    db_path = File.join(project_root, ".claude", "memory.sqlite3")
    store = ClaudeMemory::Store::SQLiteStore.new(db_path)
    block&.call(store)
    store.close
    db_path
  end

  def insert_fact(store, predicate:, object:, status: "active", entity: "test-repo", type: "repo")
    entity_id = store.find_or_create_entity(type: type, name: entity)
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: predicate,
      object_literal: object,
      status: status,
      scope: "project"
    )
  end

  describe "running a census" do
    it "returns empty when no databases are found" do
      FileUtils.mkdir_p(root)

      exit_code = command.call(["--root", root, "--no-global"])

      expect(exit_code).to eq(0)
      expect(stderr.string).to include("No ClaudeMemory databases found")
    end

    it "aggregates predicate counts across multiple project databases" do
      make_project_db("alpha") do |store|
        insert_fact(store, predicate: "convention", object: "use tabs")
        insert_fact(store, predicate: "convention", object: "prefer small methods")
        insert_fact(store, predicate: "decision", object: "use sqlite")
      end

      make_project_db("beta") do |store|
        insert_fact(store, predicate: "convention", object: "use two spaces")
      end

      exit_code = command.call(["--root", root, "--no-global"])

      expect(exit_code).to eq(0)
      report = JSON.parse(stdout.string)
      expect(report["database_count"]).to eq(2)
      expect(report["predicates"]["convention"]["total"]).to eq(3)
      expect(report["predicates"]["convention"]["db_count"]).to eq(2)
      expect(report["predicates"]["decision"]["total"]).to eq(1)
      expect(report["predicates"]["decision"]["db_count"]).to eq(1)
    end

    it "marks predicates as known when they are in the curated vocabulary" do
      make_project_db("gamma") do |store|
        insert_fact(store, predicate: "convention", object: "use tabs")
        insert_fact(store, predicate: "coined_by_distiller", object: "something")
      end

      command.call(["--root", root, "--no-global"])

      report = JSON.parse(stdout.string)
      expect(report["predicates"]["convention"]["known"]).to be(true)
      expect(report["predicates"]["coined_by_distiller"]["known"]).to be(false)
      expect(report["novel_predicates"]).to include("coined_by_distiller")
      expect(report["novel_predicates"]).not_to include("convention")
    end

    it "omits paths and content from the report" do
      make_project_db("secretproject") do |store|
        insert_fact(store, predicate: "convention", object: "super secret rule",
          entity: "secret-entity")
      end

      command.call(["--root", root, "--no-global"])

      output = stdout.string
      expect(output).not_to include("secretproject")
      expect(output).not_to include("super secret rule")
      expect(output).not_to include("secret-entity")
      expect(output).not_to include(root)
    end

    it "uses stable database ids derived from path hashes" do
      path = make_project_db("delta") { |store| insert_fact(store, predicate: "convention", object: "x") }

      command.call(["--root", root, "--no-global"])

      report = JSON.parse(stdout.string)
      expect(report["databases"].size).to eq(1)
      expected_id = Digest::SHA256.hexdigest(path)[0, 12]
      expect(report["databases"].first["id"]).to eq(expected_id)
    end

    it "flags synonym candidates by token overlap with known predicates" do
      make_project_db("epsilon") do |store|
        insert_fact(store, predicate: "has_convention", object: "x")
        insert_fact(store, predicate: "team_convention", object: "y")
      end

      command.call(["--root", root, "--no-global"])

      report = JSON.parse(stdout.string)
      novel = report["synonym_candidates"].map { |c| c["novel"] }
      expect(novel).to include("has_convention", "team_convention")
      report["synonym_candidates"].each do |candidate|
        expect(candidate["closest_known"]).to eq("convention")
        expect(candidate["overlap"]).to be > 0
      end
    end

    it "breaks out facts by status in totals and predicates" do
      make_project_db("zeta") do |store|
        insert_fact(store, predicate: "convention", object: "a", status: "active")
        insert_fact(store, predicate: "convention", object: "b", status: "superseded")
      end

      command.call(["--root", root, "--no-global"])

      report = JSON.parse(stdout.string)
      expect(report["totals"]["facts"]["active"]).to eq(1)
      expect(report["totals"]["facts"]["superseded"]).to eq(1)
      expect(report["predicates"]["convention"]["by_status"]).to eq("active" => 1, "superseded" => 1)
    end

    it "writes JSON to --output when provided" do
      make_project_db("eta") { |store| insert_fact(store, predicate: "convention", object: "x") }
      output_file = File.join(tmpdir, "census.json")

      exit_code = command.call(["--root", root, "--no-global", "--output", output_file])

      expect(exit_code).to eq(0)
      expect(File.exist?(output_file)).to be(true)
      parsed = JSON.parse(File.read(output_file))
      expect(parsed["database_count"]).to eq(1)
      expect(stderr.string).to include("scanned 1 database")
    end

    it "includes schema_version and top predicates per database" do
      make_project_db("theta") do |store|
        3.times { |i| insert_fact(store, predicate: "convention", object: "c#{i}") }
        insert_fact(store, predicate: "decision", object: "d1")
      end

      command.call(["--root", root, "--no-global"])

      report = JSON.parse(stdout.string)
      entry = report["databases"].first
      expect(entry["schema_version"]).to be_a(Integer)
      expect(entry["top_predicates"]).to include("convention" => 3)
      expect(entry["top_predicates"]).to include("decision" => 1)
      expect(entry["facts"]["active"]).to eq(4)
    end
  end
end
