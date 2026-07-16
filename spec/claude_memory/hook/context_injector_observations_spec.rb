# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Hook::ContextInjector, "observations (Block 1)" do
  let(:tmpdir) { Dir.mktmpdir("ctx_obs_#{Process.pid}") }
  let(:manager) do
    ClaudeMemory::Store::StoreManager.new(
      global_db_path: File.join(tmpdir, "global.sqlite3"),
      project_db_path: File.join(tmpdir, "project.sqlite3"),
      project_path: tmpdir
    )
  end
  let(:injector) { described_class.new(manager, source: "startup") }

  before { manager.ensure_both! }

  after do
    manager.close
    FileUtils.rm_rf(tmpdir)
  end

  it "injects an Observations section and tracks the emitted count" do
    manager.project_store.insert_observation(body: "decided to add episodic layer", priority: 1, observed_at: "2026-06-16T00:00:00Z")
    manager.project_store.insert_observation(body: "prefer do...end blocks", priority: 2, observed_at: "2026-06-15T00:00:00Z")

    context = injector.generate_context

    expect(context).to include("## Observations (what happened)")
    expect(context).to match(/- \[#\d+\] 🔴 decided to add episodic layer/)
    expect(context).to match(/- \[#\d+\] prefer do\.\.\.end blocks/)
    expect(injector.emitted_observation_count).to eq(2)
  end

  it "places observations (Block 1) ahead of the undistilled tail (Block 2)" do
    manager.project_store.insert_observation(body: "an observation", priority: 1)
    text = "x" * 400
    manager.project_store.upsert_content_item(
      source: "transcript", session_id: "s1",
      text_hash: Digest::SHA256.hexdigest(text), byte_len: text.bytesize, raw_text: text
    )

    context = injector.generate_context

    expect(context).to include("## Observations")
    expect(context).to include("## Pending Knowledge Extraction")
    expect(context.index("## Observations")).to be < context.index("## Pending Knowledge Extraction")
  end

  it "omits the section and reports zero when there are no observations" do
    context = injector.generate_context.to_s
    expect(context).not_to include("## Observations")
    expect(injector.emitted_observation_count).to eq(0)
  end

  it "injects a prominent, standalone observation-capture prompt when undistilled content exists (#72)" do
    text = "x" * 400
    manager.project_store.upsert_content_item(
      source: "transcript", session_id: "s1",
      text_hash: Digest::SHA256.hexdigest(text), byte_len: text.bytesize, raw_text: text
    )

    context = injector.generate_context

    # the fact deep-distill prompt and the episodic-capture prompt are now
    # separate sections — the latter is no longer a buried paragraph.
    expect(context).to include("## Pending Knowledge Extraction")
    expect(context).to include("## Log What Happened (episodic memory)")
    expect(context).to include("`observations` array")
    expect(context).to match(/what happened/i)
  end

  it "keeps the episodic-capture ask out of the fact deep-distill prompt" do
    text = "x" * 400
    manager.project_store.upsert_content_item(
      source: "transcript", session_id: "s1",
      text_hash: Digest::SHA256.hexdigest(text), byte_len: text.bytesize, raw_text: text
    )

    injector.generate_context
    distill_only = ClaudeMemory::Hook::ContextPresenter.distillation_prompt(injector.send(:fetch_undistilled, 5))
    expect(distill_only).not_to include("observations")
  end

  it "surfaces an Observation Reflection section for corroborated, unpromoted observations" do
    id = manager.project_store.insert_observation(body: "use SQLite for storage", priority: 1)
    manager.project_store.increment_corroboration(id, by: 2) # count 3 >= threshold

    context = injector.generate_context

    expect(context).to include("## Observation Reflection")
    expect(context).to include("memory.promote_observation")
    expect(context).to include("memory.consolidate_observations")
    expect(context).to include("[obs ##{id} ×3] use SQLite for storage")
  end

  it "omits the reflection section when nothing is corroborated yet" do
    manager.project_store.insert_observation(body: "seen once", priority: 1) # count 1

    expect(injector.generate_context.to_s).not_to include("## Observation Reflection")
  end

  describe "#reflection_context (PreCompact)" do
    it "returns only the reflection section, not the full snapshot, when candidates exist" do
      id = manager.project_store.insert_observation(body: "use SQLite for storage", priority: 1)
      manager.project_store.increment_corroboration(id, by: 2)

      reflection = injector.reflection_context

      expect(reflection).to include("## Observation Reflection")
      expect(reflection).to include("memory.consolidate_observations")
      expect(reflection).not_to include("## Decisions") # not the full context snapshot
    end

    it "returns nil when nothing is corroborated yet" do
      manager.project_store.insert_observation(body: "seen once", priority: 1)
      expect(injector.reflection_context).to be_nil
    end
  end

  it "excludes consolidated (tombstoned) observations" do
    keep = manager.project_store.insert_observation(body: "active note", priority: 1)
    gone = manager.project_store.insert_observation(body: "merged away", priority: 1)
    manager.project_store.tombstone_observation(gone, into_id: keep)

    context = injector.generate_context

    expect(context).to include("active note")
    expect(context).not_to include("merged away")
    expect(injector.emitted_observation_count).to eq(1)
  end
end
