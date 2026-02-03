# frozen_string_literal: true

require "spec_helper"
require "claude_memory/core/fact_graph"

RSpec.describe ClaudeMemory::Core::FactGraph do
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(":memory:") }
  let(:entity_id) { store.find_or_create_entity(type: "repo", name: "TestRepo") }

  let!(:fact_1) do
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: "uses_database",
      object_literal: "SQLite",
      scope: "project"
    )
  end

  let!(:fact_2) do
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: "uses_database",
      object_literal: "PostgreSQL",
      scope: "project"
    )
  end

  let!(:fact_3) do
    store.insert_fact(
      subject_entity_id: entity_id,
      predicate: "uses_database",
      object_literal: "MySQL",
      scope: "project"
    )
  end

  describe ".build" do
    context "with no relationships" do
      it "returns single node and no edges" do
        graph = described_class.build(store, fact_1)

        expect(graph[:root_fact_id]).to eq(fact_1)
        expect(graph[:node_count]).to eq(1)
        expect(graph[:edge_count]).to eq(0)
        expect(graph[:nodes].first[:id]).to eq(fact_1)
        expect(graph[:edges]).to be_empty
      end
    end

    context "with supersession links" do
      before do
        store.insert_fact_link(from_fact_id: fact_2, to_fact_id: fact_1, link_type: "supersedes")
      end

      it "includes superseded facts in graph" do
        graph = described_class.build(store, fact_2, depth: 1)

        expect(graph[:node_count]).to eq(2)
        expect(graph[:nodes].map { |n| n[:id] }).to contain_exactly(fact_1, fact_2)
      end

      it "includes supersedes edges" do
        graph = described_class.build(store, fact_2, depth: 1)

        edge = graph[:edges].find { |e| e[:type] == "supersedes" }
        expect(edge[:from]).to eq(fact_2)
        expect(edge[:to]).to eq(fact_1)
      end

      it "traverses chain at depth 2" do
        store.insert_fact_link(from_fact_id: fact_3, to_fact_id: fact_2, link_type: "supersedes")

        graph = described_class.build(store, fact_3, depth: 2)

        expect(graph[:node_count]).to eq(3)
        expect(graph[:edge_count]).to eq(2)
      end

      it "respects depth limit" do
        store.insert_fact_link(from_fact_id: fact_3, to_fact_id: fact_2, link_type: "supersedes")

        graph = described_class.build(store, fact_3, depth: 1)

        # At depth 1, only fact_3 and fact_2 (direct link)
        expect(graph[:node_count]).to eq(2)
      end
    end

    context "with conflict links" do
      before do
        store.insert_conflict(fact_a_id: fact_1, fact_b_id: fact_2)
      end

      it "includes conflicting facts in graph" do
        graph = described_class.build(store, fact_1, depth: 1)

        expect(graph[:node_count]).to eq(2)
        expect(graph[:nodes].map { |n| n[:id] }).to contain_exactly(fact_1, fact_2)
      end

      it "includes conflicts edges with status" do
        graph = described_class.build(store, fact_1, depth: 1)

        edge = graph[:edges].find { |e| e[:type] == "conflicts" }
        expect(edge).not_to be_nil
        expect(edge[:status]).to eq("open")
      end
    end

    context "with mixed relationships" do
      before do
        store.insert_fact_link(from_fact_id: fact_2, to_fact_id: fact_1, link_type: "supersedes")
        store.insert_conflict(fact_a_id: fact_2, fact_b_id: fact_3)
      end

      it "includes all related facts" do
        graph = described_class.build(store, fact_2, depth: 1)

        expect(graph[:node_count]).to eq(3)
        expect(graph[:edge_count]).to eq(2)
      end
    end

    context "with non-existent fact" do
      it "returns empty graph" do
        graph = described_class.build(store, 9999)

        expect(graph[:node_count]).to eq(0)
        expect(graph[:edges]).to be_empty
      end
    end

    context "depth clamping" do
      it "clamps depth to minimum 1" do
        graph = described_class.build(store, fact_1, depth: 0)

        expect(graph[:depth]).to eq(1)
      end

      it "clamps depth to maximum 5" do
        graph = described_class.build(store, fact_1, depth: 10)

        expect(graph[:depth]).to eq(5)
      end
    end

    context "edge deduplication" do
      it "deduplicates edges with same from/to/type" do
        edges = [
          {from: 1, to: 2, type: "supersedes"},
          {from: 1, to: 2, type: "supersedes"},
          {from: 1, to: 2, type: "conflicts"}
        ]

        result = described_class.dedupe_edges(edges)

        expect(result.size).to eq(2)
      end
    end
  end

  describe ".build_node" do
    it "builds minimal node from fact" do
      fact = described_class.build_node(
        id: 1,
        subject_name: "repo",
        predicate: "uses_db",
        object_literal: "PG",
        status: "active",
        scope: "project"
      )

      expect(fact[:id]).to eq(1)
      expect(fact[:subject]).to eq("repo")
      expect(fact[:predicate]).to eq("uses_db")
      expect(fact[:object]).to eq("PG")
      expect(fact[:status]).to eq("active")
      expect(fact[:scope]).to eq("project")
    end
  end
end
