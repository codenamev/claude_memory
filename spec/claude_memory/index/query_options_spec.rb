# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Index::QueryOptions do
  describe "#initialize" do
    it "creates query options with required parameters" do
      options = described_class.new(query_text: "database")

      expect(options.query_text).to eq("database")
      expect(options.limit).to eq(20) # default
      expect(options.scope).to eq(:all) # default
      expect(options.source).to be_nil # default
    end

    it "accepts all parameters" do
      options = described_class.new(
        query_text: "framework",
        limit: 10,
        scope: :project,
        source: :global
      )

      expect(options.query_text).to eq("framework")
      expect(options.limit).to eq(10)
      expect(options.scope).to eq(:project)
      expect(options.source).to eq(:global)
    end

    it "freezes the object (immutability)" do
      options = described_class.new(query_text: "test")
      expect(options).to be_frozen
    end

    it "converts scope string to symbol" do
      options = described_class.new(query_text: "test", scope: "project")
      expect(options.scope).to eq(:project)
    end

    it "converts source string to symbol" do
      options = described_class.new(query_text: "test", source: "global")
      expect(options.source).to eq(:global)
    end
  end

  describe "#for_project" do
    it "creates new options with project source" do
      original = described_class.new(
        query_text: "database",
        limit: 10,
        scope: :all
      )

      project_options = original.for_project

      expect(project_options.query_text).to eq("database")
      expect(project_options.limit).to eq(10)
      expect(project_options.scope).to eq(:all)
      expect(project_options.source).to eq(:project)
    end

    it "preserves immutability of original" do
      original = described_class.new(query_text: "test")
      project_options = original.for_project

      expect(original.source).to be_nil
      expect(project_options.source).to eq(:project)
    end
  end

  describe "#for_global" do
    it "creates new options with global source" do
      original = described_class.new(
        query_text: "database",
        limit: 10,
        scope: :all
      )

      global_options = original.for_global

      expect(global_options.query_text).to eq("database")
      expect(global_options.limit).to eq(10)
      expect(global_options.scope).to eq(:all)
      expect(global_options.source).to eq(:global)
    end
  end

  describe "#with_limit" do
    it "creates new options with different limit" do
      original = described_class.new(query_text: "test", limit: 10)
      new_options = original.with_limit(50)

      expect(original.limit).to eq(10)
      expect(new_options.limit).to eq(50)
      expect(new_options.query_text).to eq("test")
    end
  end

  describe "#==" do
    it "returns true for options with same values" do
      opts1 = described_class.new(query_text: "test", limit: 10, scope: :project)
      opts2 = described_class.new(query_text: "test", limit: 10, scope: :project)

      expect(opts1).to eq(opts2)
    end

    it "returns false for options with different values" do
      opts1 = described_class.new(query_text: "test", limit: 10)
      opts2 = described_class.new(query_text: "test", limit: 20)

      expect(opts1).not_to eq(opts2)
    end
  end

  describe "scope constants" do
    it "defines SCOPE_ALL" do
      expect(ClaudeMemory::Index::QueryOptions::SCOPE_ALL).to eq(:all)
    end

    it "defines SCOPE_PROJECT" do
      expect(ClaudeMemory::Index::QueryOptions::SCOPE_PROJECT).to eq(:project)
    end

    it "defines SCOPE_GLOBAL" do
      expect(ClaudeMemory::Index::QueryOptions::SCOPE_GLOBAL).to eq(:global)
    end
  end

  describe "defaults" do
    it "uses DEFAULT_LIMIT" do
      options = described_class.new(query_text: "test")
      expect(options.limit).to eq(described_class::DEFAULT_LIMIT)
    end

    it "uses DEFAULT_SCOPE" do
      options = described_class.new(query_text: "test")
      expect(options.scope).to eq(described_class::DEFAULT_SCOPE)
    end
  end
end
