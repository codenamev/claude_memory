# frozen_string_literal: true

require "spec_helper"
require "claude_memory/mcp/response_formatter"

RSpec.describe ClaudeMemory::MCP::ResponseFormatter do
  describe ".format_recall_results" do
    it "formats recall results into MCP response" do
      results = [
        {
          fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", status: "active"},
          source: :project,
          receipts: [{quote: "We use Ruby", strength: "stated"}]
        }
      ]

      response = described_class.format_recall_results(results)

      expect(response[:facts].length).to eq(1)
      expect(response[:facts][0][:id]).to eq(1)
      expect(response[:facts][0][:subject]).to eq("repo")
    end

    it "handles empty results" do
      response = described_class.format_recall_results([])

      expect(response[:facts]).to eq([])
    end
  end

  describe ".format_recall_fact" do
    it "formats single recall fact with all fields" do
      result = {
        fact: {
          id: 42,
          subject_name: "repo",
          predicate: "uses_database",
          object_literal: "PostgreSQL",
          status: "active"
        },
        source: :project,
        receipts: [{quote: "Using Postgres", strength: "stated"}]
      }

      fact = described_class.format_recall_fact(result)

      expect(fact[:id]).to eq(42)
      expect(fact[:subject]).to eq("repo")
      expect(fact[:predicate]).to eq("uses_database")
      expect(fact[:object]).to eq("PostgreSQL")
      expect(fact[:status]).to eq("active")
      expect(fact[:source]).to eq(:project)
      expect(fact[:receipts].length).to eq(1)
    end

    it "formats multiple receipts" do
      result = {
        fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", status: "active"},
        source: :global,
        receipts: [
          {quote: "Ruby is great", strength: "stated"},
          {quote: "We prefer Ruby", strength: "inferred"}
        ]
      }

      fact = described_class.format_recall_fact(result)

      expect(fact[:receipts].length).to eq(2)
      expect(fact[:receipts][0][:quote]).to eq("Ruby is great")
      expect(fact[:receipts][1][:strength]).to eq("inferred")
    end
  end

  describe ".format_index_results" do
    it "formats index results with token metadata" do
      results = [
        {id: 1, subject: "repo", predicate: "uses", object_preview: "Ruby...", status: "active",
         scope: "project", confidence: 0.9, token_estimate: 50, source: :project},
        {id: 2, subject: "repo", predicate: "prefers", object_preview: "TDD...", status: "active",
         scope: "global", confidence: 0.8, token_estimate: 30, source: :global}
      ]

      response = described_class.format_index_results("Ruby", "all", results)

      expect(response[:query]).to eq("Ruby")
      expect(response[:scope]).to eq("all")
      expect(response[:result_count]).to eq(2)
      expect(response[:total_estimated_tokens]).to eq(80)
      expect(response[:facts].length).to eq(2)
    end

    it "handles empty results" do
      response = described_class.format_index_results("query", "project", [])

      expect(response[:result_count]).to eq(0)
      expect(response[:total_estimated_tokens]).to eq(0)
      expect(response[:facts]).to eq([])
    end
  end

  describe ".format_index_fact" do
    it "formats single index fact with all fields" do
      result = {
        id: 10,
        subject: "app",
        predicate: "uses_framework",
        object_preview: "Rails 7...",
        status: "active",
        scope: "project",
        confidence: 0.95,
        token_estimate: 40,
        source: :project
      }

      fact = described_class.format_index_fact(result)

      expect(fact[:id]).to eq(10)
      expect(fact[:subject]).to eq("app")
      expect(fact[:predicate]).to eq("uses_framework")
      expect(fact[:object_preview]).to eq("Rails 7...")
      expect(fact[:status]).to eq("active")
      expect(fact[:scope]).to eq("project")
      expect(fact[:confidence]).to eq(0.95)
      expect(fact[:tokens]).to eq(40)
      expect(fact[:source]).to eq(:project)
    end
  end

  describe ".format_explanation" do
    it "formats explanation with fact, receipts, and relationships" do
      explanation = {
        fact: {
          id: 5,
          subject_name: "repo",
          predicate: "uses",
          object_literal: "Ruby 3.2",
          status: "active",
          valid_from: "2024-01-01",
          valid_to: nil
        },
        receipts: [{quote: "Using Ruby 3.2", strength: "stated"}],
        supersedes: [3, 4],
        superseded_by: [],
        conflicts: [{id: 10, status: "open"}]
      }

      formatted = described_class.format_explanation(explanation, "project")

      expect(formatted[:fact][:id]).to eq(5)
      expect(formatted[:fact][:subject]).to eq("repo")
      expect(formatted[:fact][:predicate]).to eq("uses")
      expect(formatted[:fact][:object]).to eq("Ruby 3.2")
      expect(formatted[:source]).to eq("project")
      expect(formatted[:receipts].length).to eq(1)
      expect(formatted[:supersedes]).to eq([3, 4])
      expect(formatted[:superseded_by]).to eq([])
      expect(formatted[:conflicts]).to eq([10])
    end

    it "extracts conflict IDs only" do
      explanation = {
        fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", status: "active",
               valid_from: nil, valid_to: nil},
        receipts: [],
        supersedes: [],
        superseded_by: [],
        conflicts: [{id: 20, status: "open"}, {id: 21, status: "resolved"}]
      }

      formatted = described_class.format_explanation(explanation, "global")

      expect(formatted[:conflicts]).to eq([20, 21])
    end
  end

  describe ".format_detailed_explanation" do
    it "formats detailed explanation with full relationships" do
      explanation = {
        fact: {
          id: 7,
          subject_name: "app",
          predicate: "convention",
          object_literal: "4-space indent",
          status: "active",
          confidence: 0.9,
          scope: "global",
          valid_from: "2024-01-01",
          valid_to: nil
        },
        receipts: [
          {quote: "Use 4 spaces", strength: "stated", session_id: "abc123", occurred_at: "2024-01-01T10:00:00Z"}
        ],
        supersedes: [5],
        superseded_by: [],
        conflicts: [{id: 15, status: "open"}]
      }

      formatted = described_class.format_detailed_explanation(explanation)

      expect(formatted[:fact][:id]).to eq(7)
      expect(formatted[:fact][:confidence]).to eq(0.9)
      expect(formatted[:fact][:scope]).to eq("global")
      expect(formatted[:receipts][0][:session_id]).to eq("abc123")
      expect(formatted[:receipts][0][:occurred_at]).to eq("2024-01-01T10:00:00Z")
      expect(formatted[:relationships][:supersedes]).to eq([5])
      expect(formatted[:relationships][:conflicts]).to eq([{id: 15, status: "open"}])
    end

    it "includes conflict status in relationships" do
      explanation = {
        fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", status: "active",
               confidence: 0.8, scope: "project", valid_from: nil, valid_to: nil},
        receipts: [],
        supersedes: [],
        superseded_by: [10],
        conflicts: [{id: 25, status: "resolved"}, {id: 26, status: "open"}]
      }

      formatted = described_class.format_detailed_explanation(explanation)

      expect(formatted[:relationships][:conflicts].length).to eq(2)
      expect(formatted[:relationships][:conflicts][0]).to eq({id: 25, status: "resolved"})
      expect(formatted[:relationships][:conflicts][1]).to eq({id: 26, status: "open"})
    end
  end

  describe ".format_receipt" do
    it "formats receipt with minimal fields" do
      receipt = {quote: "We use Ruby", strength: "stated", session_id: "x", occurred_at: "2024-01-01"}

      formatted = described_class.format_receipt(receipt)

      expect(formatted[:quote]).to eq("We use Ruby")
      expect(formatted[:strength]).to eq("stated")
      expect(formatted).not_to have_key(:session_id)
      expect(formatted).not_to have_key(:occurred_at)
    end

    it "handles empty quote" do
      receipt = {quote: "", strength: "inferred"}

      formatted = described_class.format_receipt(receipt)

      expect(formatted[:quote]).to eq("")
      expect(formatted[:strength]).to eq("inferred")
    end
  end

  describe ".format_detailed_receipt" do
    it "formats detailed receipt with all fields" do
      receipt = {
        quote: "Built with Rails",
        strength: "stated",
        session_id: "session-123",
        occurred_at: "2024-01-15T14:30:00Z"
      }

      formatted = described_class.format_detailed_receipt(receipt)

      expect(formatted[:quote]).to eq("Built with Rails")
      expect(formatted[:strength]).to eq("stated")
      expect(formatted[:session_id]).to eq("session-123")
      expect(formatted[:occurred_at]).to eq("2024-01-15T14:30:00Z")
    end
  end
end
