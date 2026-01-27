# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Recall::DualQueryTemplate do
  let(:project_store) { double("ProjectStore") }
  let(:global_store) { double("GlobalStore") }
  let(:manager) do
    double("StoreManager").tap do |m|
      allow(m).to receive(:project_exists?).and_return(true)
      allow(m).to receive(:global_exists?).and_return(true)
      allow(m).to receive(:project_store).and_return(project_store)
      allow(m).to receive(:global_store).and_return(global_store)
      allow(m).to receive(:ensure_project!)
      allow(m).to receive(:ensure_global!)
    end
  end

  let(:template) { described_class.new(manager) }

  describe "#execute" do
    context "with scope: 'all'" do
      it "queries both project and global stores" do
        results = template.execute(scope: "all") do |store, source|
          [{store: store, source: source}]
        end

        expect(results).to contain_exactly(
          {store: project_store, source: :project},
          {store: global_store, source: :global}
        )
      end

      it "ensures both stores" do
        expect(manager).to receive(:ensure_project!)
        expect(manager).to receive(:ensure_global!)

        template.execute(scope: "all") { |store, source| [] }
      end
    end

    context "with scope: 'project'" do
      it "queries only project store" do
        results = template.execute(scope: "project") do |store, source|
          [{store: store, source: source}]
        end

        expect(results).to contain_exactly(
          {store: project_store, source: :project}
        )
      end

      it "does not query global store" do
        expect(manager).not_to receive(:global_store)

        template.execute(scope: "project") { |store, source| [] }
      end
    end

    context "with scope: 'global'" do
      it "queries only global store" do
        results = template.execute(scope: "global") do |store, source|
          [{store: store, source: source}]
        end

        expect(results).to contain_exactly(
          {store: global_store, source: :global}
        )
      end

      it "does not query project store" do
        expect(manager).not_to receive(:project_store)

        template.execute(scope: "global") { |store, source| [] }
      end
    end

    context "when project store does not exist" do
      before do
        allow(manager).to receive(:project_exists?).and_return(false)
      end

      it "skips project store even with scope 'all'" do
        results = template.execute(scope: "all") do |store, source|
          [{store: store, source: source}]
        end

        expect(results).to contain_exactly(
          {store: global_store, source: :global}
        )
      end
    end

    context "when global store does not exist" do
      before do
        allow(manager).to receive(:global_exists?).and_return(false)
      end

      it "skips global store even with scope 'all'" do
        results = template.execute(scope: "all") do |store, source|
          [{store: store, source: source}]
        end

        expect(results).to contain_exactly(
          {store: project_store, source: :project}
        )
      end
    end

    context "when store returns nil" do
      before do
        allow(manager).to receive(:project_store).and_return(nil)
      end

      it "skips nil stores" do
        results = template.execute(scope: "all") do |store, source|
          [{store: store, source: source}]
        end

        expect(results).to contain_exactly(
          {store: global_store, source: :global}
        )
      end
    end

    context "when block returns empty array" do
      it "returns empty results" do
        results = template.execute(scope: "all") { |store, source| [] }

        expect(results).to eq([])
      end
    end

    context "when block returns multiple items" do
      it "flattens and concatenates all results" do
        results = template.execute(scope: "all") do |store, source|
          [
            {id: 1, source: source},
            {id: 2, source: source}
          ]
        end

        expect(results.size).to eq(4)  # 2 from project + 2 from global
        expect(results).to include(
          {id: 1, source: :project},
          {id: 2, source: :project},
          {id: 1, source: :global},
          {id: 2, source: :global}
        )
      end
    end
  end
end
