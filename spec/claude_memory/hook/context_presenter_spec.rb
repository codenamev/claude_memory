# frozen_string_literal: true

require "spec_helper"

# Pure presentation — no store, no manager, no DB.
RSpec.describe ClaudeMemory::Hook::ContextPresenter do
  describe ".section" do
    it "renders a titled bullet list" do
      out = described_class.section("Decisions", ["use SQLite", "prefer do...end"])
      expect(out).to eq("## Decisions\n- use SQLite\n- prefer do...end")
    end

    it "compacts and de-dupes, returning nil when empty" do
      expect(described_class.section("X", [nil, nil])).to be_nil
      expect(described_class.section("X", ["a", "a", nil])).to eq("## X\n- a")
    end
  end

  describe ".fact_line" do
    it "formats subject.predicate = object" do
      fact = {subject_name: "repo", predicate: "uses_database", object_literal: "sqlite"}
      expect(described_class.fact_line(fact, stale_threshold_days: 14)).to eq("repo.uses_database = sqlite")
    end

    it "falls back to the bare object when subject/predicate are missing" do
      expect(described_class.fact_line({object_literal: "just a note"}, stale_threshold_days: 14))
        .to eq("just a note")
    end

    it "returns nil when there is nothing to render" do
      expect(described_class.fact_line({}, stale_threshold_days: 14)).to be_nil
      expect(described_class.fact_line(nil, stale_threshold_days: 14)).to be_nil
    end
  end

  describe ".observation_reflection" do
    it "lists candidates with promote/consolidate instructions" do
      out = described_class.observation_reflection([{id: 7, corroboration_count: 3, body: "use SQLite"}])
      expect(out).to include("## Observation Reflection")
      expect(out).to include("memory.promote_observation")
      expect(out).to include("[obs #7 ×3] use SQLite")
    end
  end

  describe ".distillation_prompt" do
    it "renders content items with relative time and truncated text" do
      out = described_class.distillation_prompt([{id: 42, occurred_at: nil, raw_text: "hello world"}])
      expect(out).to include("## Pending Knowledge Extraction")
      expect(out).to include("### Content Item 42")
      expect(out).to include("hello world")
    end
  end

  describe ".observation_capture_prompt" do
    it "is a standalone episodic-capture ask" do
      expect(described_class.observation_capture_prompt).to include("## Log What Happened")
    end
  end

  describe ".auto_memory_mirror" do
    it "renders candidate name and content" do
      out = described_class.auto_memory_mirror([{name: "gotcha_x", content: "watch out"}])
      expect(out).to include("## Auto-Memory Mirror Candidates")
      expect(out).to include("### gotcha_x")
      expect(out).to include("watch out")
    end
  end
end
