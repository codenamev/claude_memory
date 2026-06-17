# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Observe::ObservationsRenderer do
  def obs(body:, priority: 3, observed_at: nil)
    {body: body, priority: priority, observed_at: observed_at}
  end

  describe ".render" do
    it "returns nil for an empty or blank-only set" do
      expect(described_class.render([])).to be_nil
      expect(described_class.render(nil)).to be_nil
      expect(described_class.render([obs(body: "   ")])).to be_nil
    end

    it "renders a titled, intro'd block with one line per observation" do
      out = described_class.render([obs(body: "did a thing")])

      expect(out).to start_with("## Observations (what happened)")
      expect(out).to include("complements the facts above")
      expect(out).to include("- did a thing")
    end

    it "marks only important (priority 1) lines with 🔴 and strips 🟡/🟢" do
      out = described_class.render([
        obs(body: "important one", priority: 1),
        obs(body: "maybe one", priority: 2),
        obs(body: "info one", priority: 3)
      ])

      expect(out).to include("- 🔴 important one")
      expect(out).to include("- maybe one")
      expect(out).to include("- info one")
      expect(out).not_to include("🟡")
      expect(out).not_to include("🟢")
    end

    it "appends a relative time when observed_at is present" do
      out = described_class.render([obs(body: "x", observed_at: "2026-01-01T00:00:00Z")])
      expect(out).to match(/- x \(.+\)/)
    end

    it "tags each line with the observation id when present (for promote/consolidate reference)" do
      out = described_class.render([obs(body: "x").merge(id: 42)])
      expect(out).to include("- [#42] x")
    end

    it "omits the id tag when the row has no id" do
      expect(described_class.render([obs(body: "x")])).to include("- x")
    end

    it "honors a custom title and can omit the intro" do
      out = described_class.render([obs(body: "x")], title: "Project Observations", intro: false)
      expect(out).to start_with("## Project Observations")
      expect(out).not_to include("complements the facts above")
    end
  end
end
