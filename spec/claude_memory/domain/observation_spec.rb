# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Domain::Observation do
  describe "#initialize" do
    it "creates an observation with required attributes" do
      obs = described_class.new(id: 1, body: "decided to use SQLite", kind: "decision", priority: 1)

      expect(obs.id).to eq(1)
      expect(obs.body).to eq("decided to use SQLite")
      expect(obs.kind).to eq("decision")
      expect(obs.priority).to eq(1)
    end

    it "defaults kind to event, priority to info, scope to project, status to active" do
      obs = described_class.new(body: "something happened")

      expect(obs.kind).to eq("event")
      expect(obs.priority).to eq(described_class::INFO)
      expect(obs.scope).to eq("project")
      expect(obs.status).to eq("active")
    end

    it "raises when body is blank" do
      expect { described_class.new(body: "") }.to raise_error(ArgumentError, /body required/)
      expect { described_class.new(body: nil) }.to raise_error(ArgumentError, /body required/)
    end

    it "raises when priority is out of range" do
      expect { described_class.new(body: "x", priority: 0) }.to raise_error(ArgumentError, /priority/)
      expect { described_class.new(body: "x", priority: 4) }.to raise_error(ArgumentError, /priority/)
    end

    it "is frozen (immutable)" do
      expect(described_class.new(body: "x")).to be_frozen
    end
  end

  describe "status and priority predicates" do
    it "#active? reflects status" do
      expect(described_class.new(body: "x", status: "active")).to be_active
      expect(described_class.new(body: "x", status: "consolidated")).not_to be_active
    end

    it "#consolidated? reflects status" do
      expect(described_class.new(body: "x", status: "consolidated")).to be_consolidated
    end

    it "#important? is true only for priority 1" do
      expect(described_class.new(body: "x", priority: described_class::IMPORTANT)).to be_important
      expect(described_class.new(body: "x", priority: described_class::MAYBE)).not_to be_important
    end

    it "#global? reflects scope" do
      expect(described_class.new(body: "x", scope: "global")).to be_global
      expect(described_class.new(body: "x", scope: "project")).not_to be_global
    end

    it "#expired? reflects status" do
      expect(described_class.new(body: "x", status: "expired")).to be_expired
    end
  end

  describe "promotion" do
    it "defaults corroboration_count to 1" do
      expect(described_class.new(body: "x").corroboration_count).to eq(1)
    end

    it "#promoted? is true once promoted_at is set" do
      expect(described_class.new(body: "x")).not_to be_promoted
      expect(described_class.new(body: "x", promoted_at: "2026-06-17T00:00:00Z", promoted_fact_id: 9)).to be_promoted
    end

    it "#corroborated? compares against a threshold" do
      expect(described_class.new(body: "x", corroboration_count: 2)).to be_corroborated(2)
      expect(described_class.new(body: "x", corroboration_count: 1)).not_to be_corroborated(2)
    end
  end

  describe "#to_h" do
    it "round-trips all attributes" do
      attrs = {
        id: 7, body: "b", kind: "preference", priority: 2, scope: "global",
        project_path: nil, source_content_item_id: 3, consolidated_into: nil,
        token_count: 5, status: "active", session_id: "s1",
        observed_at: "2026-06-16T00:00:00Z", created_at: "2026-06-16T00:00:00Z",
        reflected_at: nil, corroboration_count: 4, promoted_at: nil, promoted_fact_id: nil
      }
      expect(described_class.new(attrs).to_h).to eq(attrs)
    end
  end
end
