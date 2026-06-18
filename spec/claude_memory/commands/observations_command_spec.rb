# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"
require "json"

RSpec.describe ClaudeMemory::Commands::ObservationsCommand do
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

  def project_store
    ClaudeMemory::Store::SQLiteStore.new(project_db_path)
  end

  # Seed a corroborated observation with a source content item for provenance.
  def seed_observation(body:, kind: "decision", priority: 1, corroboration: 1, scope: "project", path: project_db_path)
    store = ClaudeMemory::Store::SQLiteStore.new(path)
    cid = store.upsert_content_item(
      source: "test",
      text_hash: Digest::SHA256.hexdigest(body + rand.to_s),
      byte_len: body.bytesize,
      raw_text: body
    )
    id = store.insert_observation(
      body: body, kind: kind, priority: priority, scope: scope,
      project_path: (scope == "project") ? tmpdir : nil,
      source_content_item_id: cid
    )
    store.increment_corroboration(id, by: corroboration - 1) if corroboration > 1
    store.close
    id
  end

  describe "list (default)" do
    it "reports an empty timeline when the project DB has no observations" do
      project_store.close

      exit_code = command.call([])

      expect(exit_code).to eq(0)
      out = stdout.string
      expect(out).to include("Observations (episodic 'what happened' log)")
      expect(out).to include("Active: 0")
      expect(out).to include("(no observations)")
    end

    it "renders totals, kind breakdown, priority, corroboration, and timeline" do
      seed_observation(body: "use SQLite for storage", kind: "decision", priority: 1, corroboration: 2)
      seed_observation(body: "user prefers tabs", kind: "preference", priority: 2, corroboration: 1)

      exit_code = command.call([])

      expect(exit_code).to eq(0)
      out = stdout.string
      expect(out).to include("Active: 2")
      expect(out).to include("By kind (active):")
      expect(out).to include("decision")
      expect(out).to include("preference")
      expect(out).to include("By priority (active):")
      expect(out).to include("1 (important)")
      expect(out).to include("Promotable (>= 2 sightings, not yet promoted): 1")
      expect(out).to include("Recent timeline:")
      expect(out).to include("use SQLite for storage")
    end

    it "reports a compression ratio when source tokens exceed observation tokens" do
      seed_observation(body: "x", kind: "event", priority: 3, corroboration: 1)

      command.call([])

      expect(stdout.string).to include("Compression:")
      expect(stdout.string).to match(/Ratio \(source \/ observation\):/)
    end

    it "filters the timeline by --kind" do
      seed_observation(body: "decision body", kind: "decision", priority: 1)
      seed_observation(body: "event body", kind: "event", priority: 3)

      command.call(["--kind", "decision"])

      out = stdout.string
      expect(out).to include("decision body")
      expect(out).not_to include("event body")
    end

    it "honors --limit on the recent timeline" do
      5.times { |i| seed_observation(body: "obs number #{i}", kind: "event", priority: 3) }

      command.call(["--limit", "2"])

      timeline = stdout.string.split("Recent timeline:").last
      bodies = timeline.scan(/obs number \d/)
      expect(bodies.size).to eq(2)
    end

    it "emits JSON with --json" do
      seed_observation(body: "json observation", kind: "decision", priority: 1, corroboration: 2)

      exit_code = command.call(["--json"])

      expect(exit_code).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload["totals"]["active"]).to eq(1)
      expect(payload["corroboration"]["promotable"]).to eq(1)
      expect(payload["recent"].first["body"]).to eq("json observation")
    end
  end

  describe "promote" do
    it "promotes a corroborated observation into a fact" do
      id = seed_observation(body: "use SQLite for storage", kind: "decision", priority: 1, corroboration: 2)

      exit_code = command.call([
        "promote", id.to_s,
        "--predicate", "decision",
        "--object", "claude_memory uses SQLite because it is embedded and zero-config"
      ])

      expect(exit_code).to eq(0)
      expect(stdout.string).to match(/Promoted observation ##{id} -> fact #\d+/)

      store = project_store
      promoted_fact_id = store.observations.where(id: id).get(:promoted_fact_id)
      expect(promoted_fact_id).not_to be_nil
      expect(store.facts.where(id: promoted_fact_id).get(:object_literal)).to include("SQLite")
      store.close
    end

    it "refuses a one-off observation (anti-hallucination gate)" do
      id = seed_observation(body: "seen once", kind: "decision", priority: 1, corroboration: 1)

      exit_code = command.call([
        "promote", id.to_s, "--predicate", "decision", "--object", "X because Y"
      ])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/not yet corroborated/i)
      store = project_store
      expect(store.observations.where(id: id).get(:promoted_at)).to be_nil
      store.close
    end

    it "refuses to promote the same observation twice" do
      id = seed_observation(body: "use SQLite", kind: "decision", priority: 1, corroboration: 2)
      command.call(["promote", id.to_s, "--predicate", "decision", "--object", "a because b"])

      exit_code = command.call(["promote", id.to_s, "--predicate", "decision", "--object", "a because b"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/already promoted/i)
    end

    it "errors on a missing observation" do
      exit_code = command.call(["promote", "9999", "--predicate", "decision", "--object", "z because w"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/not found/i)
    end

    it "requires --predicate and --object" do
      id = seed_observation(body: "obs", kind: "decision", priority: 1, corroboration: 2)

      exit_code = command.call(["promote", id.to_s, "--predicate", "decision"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/required/i)
    end

    it "errors when no id is given" do
      exit_code = command.call(["promote", "--predicate", "decision", "--object", "x"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/Usage/i)
    end
  end

  describe "consolidate" do
    it "merges related observations and combines corroboration" do
      id1 = seed_observation(body: "uses sqlite", kind: "decision", priority: 1, corroboration: 1)
      id2 = seed_observation(body: "storage is sqlite", kind: "decision", priority: 1, corroboration: 1)

      exit_code = command.call([
        "consolidate", "#{id1},#{id2}", "--body", "claude_memory stores data in SQLite"
      ])

      expect(exit_code).to eq(0)
      expect(stdout.string).to match(/Consolidated 2 observations -> #\d+/)
      expect(stdout.string).to include("Combined corroboration: 2")

      store = project_store
      expect(store.observations.where(id: id1).get(:status)).to eq("consolidated")
      expect(store.observations.where(id: id2).get(:status)).to eq("consolidated")
      store.close
    end

    it "requires at least two ids" do
      id = seed_observation(body: "solo", kind: "event", priority: 3)

      exit_code = command.call(["consolidate", id.to_s, "--body", "synthesis"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/Usage/i)
    end

    it "requires a --body" do
      id1 = seed_observation(body: "a", kind: "event", priority: 3)
      id2 = seed_observation(body: "b", kind: "event", priority: 3)

      exit_code = command.call(["consolidate", "#{id1},#{id2}"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/body is required/i)
    end

    it "errors when fewer than two observations are active in scope" do
      id1 = seed_observation(body: "a", kind: "event", priority: 3)

      exit_code = command.call(["consolidate", "#{id1},9999", "--body", "synthesis"])

      expect(exit_code).to eq(1)
      expect(stderr.string).to match(/at least 2 active/i)
    end
  end
end
