# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/scope_filter"

RSpec.describe ClaudeMemory::Core::ScopeFilter do
  let(:project_path) { "/path/to/project" }

  describe ".matches?" do
    it "returns true for SCOPE_ALL regardless of fact scope" do
      fact = {scope: "project", project_path: project_path}
      expect(described_class.matches?(fact, "all", project_path)).to be true

      fact = {scope: "global"}
      expect(described_class.matches?(fact, "all", project_path)).to be true
    end

    it "returns true for project fact matching current project" do
      fact = {scope: "project", project_path: project_path}
      expect(described_class.matches?(fact, "project", project_path)).to be true
    end

    it "returns false for project fact from different project" do
      fact = {scope: "project", project_path: "/other/project"}
      expect(described_class.matches?(fact, "project", project_path)).to be false
    end

    it "returns true for global fact when scope is global" do
      fact = {scope: "global"}
      expect(described_class.matches?(fact, "global", project_path)).to be true
    end

    it "returns false for project fact when scope is global" do
      fact = {scope: "project", project_path: project_path}
      expect(described_class.matches?(fact, "global", project_path)).to be false
    end

    it "defaults to project scope if fact scope is missing" do
      fact = {project_path: project_path}
      expect(described_class.matches?(fact, "project", project_path)).to be true

      fact_different = {project_path: "/other/project"}
      expect(described_class.matches?(fact_different, "project", project_path)).to be false
    end

    it "returns true for unknown scope" do
      fact = {scope: "project", project_path: project_path}
      expect(described_class.matches?(fact, "unknown", project_path)).to be true
    end
  end

  describe ".filter_facts" do
    let(:project_fact) { {id: 1, scope: "project", project_path: project_path} }
    let(:global_fact) { {id: 2, scope: "global"} }
    let(:other_project_fact) { {id: 3, scope: "project", project_path: "/other"} }
    let(:facts) { [project_fact, global_fact, other_project_fact] }

    it "returns all facts for SCOPE_ALL" do
      result = described_class.filter_facts(facts, "all", project_path)
      expect(result).to eq(facts)
    end

    it "returns only current project facts for SCOPE_PROJECT" do
      result = described_class.filter_facts(facts, "project", project_path)
      expect(result).to eq([project_fact])
    end

    it "returns only global facts for SCOPE_GLOBAL" do
      result = described_class.filter_facts(facts, "global", project_path)
      expect(result).to eq([global_fact])
    end

    it "returns empty array when no facts match" do
      result = described_class.filter_facts(facts, "global", "/nowhere")
      expect(result.select { |f| f[:scope] == "global" }).to eq([global_fact])
    end
  end

  describe ".apply_to_dataset" do
    let(:mock_dataset) { double("Dataset") }

    it "filters for project scope" do
      expect(mock_dataset).to receive(:where).with(scope: "project", project_path: project_path)
      described_class.apply_to_dataset(mock_dataset, "project", project_path)
    end

    it "filters for global scope" do
      expect(mock_dataset).to receive(:where).with(scope: "global")
      described_class.apply_to_dataset(mock_dataset, "global", project_path)
    end

    it "returns unfiltered dataset for SCOPE_ALL" do
      result = described_class.apply_to_dataset(mock_dataset, "all", project_path)
      expect(result).to eq(mock_dataset)
    end

    it "returns unfiltered dataset for unknown scope" do
      result = described_class.apply_to_dataset(mock_dataset, "unknown", project_path)
      expect(result).to eq(mock_dataset)
    end
  end
end
