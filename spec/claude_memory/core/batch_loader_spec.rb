# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::BatchLoader do
  describe ".load_many" do
    let(:records) { [] }
    let(:mock_dataset) do
      double("Dataset").tap do |ds|
        allow(ds).to receive(:where).and_return(ds)
        allow(ds).to receive(:all).and_return(records)
      end
    end

    context "with empty IDs" do
      it "returns empty hash without querying" do
        result = described_class.load_many(mock_dataset, [], group_by: :single)
        expect(result).to eq({})
      end
    end

    context "with group_by: :single" do
      let(:records) do
        [
          {id: 1, name: "Alice"},
          {id: 2, name: "Bob"},
          {id: 3, name: "Charlie"}
        ]
      end

      it "returns hash indexed by ID" do
        result = described_class.load_many(mock_dataset, [1, 2, 3], group_by: :single)

        expect(result).to eq({
          1 => {id: 1, name: "Alice"},
          2 => {id: 2, name: "Bob"},
          3 => {id: 3, name: "Charlie"}
        })
      end
    end

    context "with group_by: <column_name>" do
      let(:records) do
        [
          {id: 1, fact_id: 10, data: "A"},
          {id: 2, fact_id: 10, data: "B"},
          {id: 3, fact_id: 20, data: "C"}
        ]
      end

      it "returns hash grouped by column" do
        result = described_class.load_many(mock_dataset, [1, 2, 3], group_by: :fact_id)

        expect(result).to eq({
          10 => [
            {id: 1, fact_id: 10, data: "A"},
            {id: 2, fact_id: 10, data: "B"}
          ],
          20 => [
            {id: 3, fact_id: 20, data: "C"}
          ]
        })
      end
    end

    context "with invalid group_by" do
      let(:records) { [] }

      it "raises ArgumentError" do
        expect {
          described_class.load_many(mock_dataset, [1], group_by: "invalid")
        }.to raise_error(ArgumentError, /Invalid group_by/)
      end
    end

    context "with dataset that returns empty results" do
      let(:records) { [] }

      it "returns empty hash for :single" do
        result = described_class.load_many(mock_dataset, [1, 2], group_by: :single)
        expect(result).to eq({})
      end

      it "returns empty hash for grouped" do
        result = described_class.load_many(mock_dataset, [1, 2], group_by: :fact_id)
        expect(result).to eq({})
      end
    end
  end
end
