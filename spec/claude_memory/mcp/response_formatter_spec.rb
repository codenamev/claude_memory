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

  describe ".format_changes" do
    it "formats changes list with since timestamp" do
      changes = [
        {id: 1, predicate: "uses", object_literal: "Ruby", status: "active",
         created_at: "2024-01-01T10:00:00Z", source: :project},
        {id: 2, predicate: "prefers", object_literal: "TDD", status: "active",
         created_at: "2024-01-02T11:00:00Z", source: :global}
      ]

      formatted = described_class.format_changes("2024-01-01T00:00:00Z", changes)

      expect(formatted[:since]).to eq("2024-01-01T00:00:00Z")
      expect(formatted[:changes].length).to eq(2)
      expect(formatted[:changes][0][:id]).to eq(1)
      expect(formatted[:changes][1][:source]).to eq(:global)
    end

    it "handles empty changes" do
      formatted = described_class.format_changes("2024-01-01", [])

      expect(formatted[:since]).to eq("2024-01-01")
      expect(formatted[:changes]).to eq([])
    end
  end

  describe ".format_change" do
    it "formats single change with all fields" do
      change = {
        id: 42,
        predicate: "uses_database",
        object_literal: "PostgreSQL",
        status: "active",
        created_at: "2024-01-15T14:30:00Z",
        source: :project
      }

      formatted = described_class.format_change(change)

      expect(formatted[:id]).to eq(42)
      expect(formatted[:predicate]).to eq("uses_database")
      expect(formatted[:object]).to eq("PostgreSQL")
      expect(formatted[:status]).to eq("active")
      expect(formatted[:created_at]).to eq("2024-01-15T14:30:00Z")
      expect(formatted[:source]).to eq(:project)
    end
  end

  describe ".format_conflicts" do
    it "formats conflicts list with count" do
      conflicts = [
        {id: 1, fact_a_id: 10, fact_b_id: 11, status: "open", source: :project},
        {id: 2, fact_a_id: 20, fact_b_id: 21, status: "resolved", source: :global}
      ]

      formatted = described_class.format_conflicts(conflicts)

      expect(formatted[:count]).to eq(2)
      expect(formatted[:conflicts].length).to eq(2)
      expect(formatted[:conflicts][0][:id]).to eq(1)
      expect(formatted[:conflicts][1][:status]).to eq("resolved")
    end

    it "handles empty conflicts" do
      formatted = described_class.format_conflicts([])

      expect(formatted[:count]).to eq(0)
      expect(formatted[:conflicts]).to eq([])
    end
  end

  describe ".format_conflict" do
    it "formats single conflict with all fields" do
      conflict = {
        id: 15,
        fact_a_id: 100,
        fact_b_id: 101,
        status: "open",
        source: :project
      }

      formatted = described_class.format_conflict(conflict)

      expect(formatted[:id]).to eq(15)
      expect(formatted[:fact_a]).to eq(100)
      expect(formatted[:fact_b]).to eq(101)
      expect(formatted[:status]).to eq("open")
      expect(formatted[:source]).to eq(:project)
    end
  end

  describe ".format_sweep_stats" do
    it "formats sweep statistics with all fields" do
      stats = {
        proposed_facts_expired: 5,
        disputed_facts_expired: 2,
        orphaned_provenance_deleted: 10,
        old_content_pruned: 3,
        elapsed_seconds: 2.5678
      }

      formatted = described_class.format_sweep_stats("project", stats)

      expect(formatted[:scope]).to eq("project")
      expect(formatted[:proposed_expired]).to eq(5)
      expect(formatted[:disputed_expired]).to eq(2)
      expect(formatted[:orphaned_deleted]).to eq(10)
      expect(formatted[:content_pruned]).to eq(3)
      expect(formatted[:elapsed_seconds]).to eq(2.568)
    end

    it "rounds elapsed_seconds to 3 decimal places" do
      stats = {
        proposed_facts_expired: 0,
        disputed_facts_expired: 0,
        orphaned_provenance_deleted: 0,
        old_content_pruned: 0,
        elapsed_seconds: 1.23456789
      }

      formatted = described_class.format_sweep_stats("global", stats)

      expect(formatted[:elapsed_seconds]).to eq(1.235)
    end

    it "handles zero elapsed seconds" do
      stats = {
        proposed_facts_expired: 0,
        disputed_facts_expired: 0,
        orphaned_provenance_deleted: 0,
        old_content_pruned: 0,
        elapsed_seconds: 0.0
      }

      formatted = described_class.format_sweep_stats("project", stats)

      expect(formatted[:elapsed_seconds]).to eq(0.0)
    end
  end

  describe ".format_semantic_results" do
    it "formats semantic search results with similarity" do
      results = [
        {
          fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", scope: "project"},
          source: :project,
          similarity: 0.95,
          receipts: [{quote: "We use Ruby", strength: "stated"}]
        }
      ]

      formatted = described_class.format_semantic_results("Ruby programming", "both", "all", results)

      expect(formatted[:query]).to eq("Ruby programming")
      expect(formatted[:mode]).to eq("both")
      expect(formatted[:scope]).to eq("all")
      expect(formatted[:count]).to eq(1)
      expect(formatted[:facts][0][:similarity]).to eq(0.95)
    end

    it "handles empty results" do
      formatted = described_class.format_semantic_results("query", "vector", "project", [])

      expect(formatted[:count]).to eq(0)
      expect(formatted[:facts]).to eq([])
    end
  end

  describe ".format_semantic_fact" do
    it "formats fact with similarity score" do
      result = {
        fact: {id: 10, subject_name: "app", predicate: "uses", object_literal: "Rails", scope: "project"},
        source: :project,
        similarity: 0.87,
        receipts: [{quote: "Built with Rails", strength: "stated"}]
      }

      formatted = described_class.format_semantic_fact(result)

      expect(formatted[:id]).to eq(10)
      expect(formatted[:subject]).to eq("app")
      expect(formatted[:predicate]).to eq("uses")
      expect(formatted[:object]).to eq("Rails")
      expect(formatted[:scope]).to eq("project")
      expect(formatted[:source]).to eq(:project)
      expect(formatted[:similarity]).to eq(0.87)
      expect(formatted[:receipts].length).to eq(1)
    end
  end

  describe ".format_concept_results" do
    it "formats multi-concept search results" do
      results = [
        {
          fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "PostgreSQL", scope: "project"},
          source: :project,
          similarity: 0.9,
          concept_similarities: {"database" => 0.95, "PostgreSQL" => 0.85},
          receipts: []
        }
      ]

      formatted = described_class.format_concept_results(["database", "PostgreSQL"], "all", results)

      expect(formatted[:concepts]).to eq(["database", "PostgreSQL"])
      expect(formatted[:scope]).to eq("all")
      expect(formatted[:count]).to eq(1)
      expect(formatted[:facts][0][:id]).to eq(1)
      expect(formatted[:facts][0][:average_similarity]).to eq(0.9)
      expect(formatted[:facts][0][:concept_similarities]).to eq({"database" => 0.95, "PostgreSQL" => 0.85})
    end
  end

  describe ".format_concept_fact" do
    it "formats fact with per-concept similarities" do
      result = {
        fact: {id: 5, subject_name: "app", predicate: "uses", object_literal: "Rails + Postgres", scope: "project"},
        source: :project,
        similarity: 0.88,
        concept_similarities: {"Rails" => 0.9, "Postgres" => 0.86},
        receipts: [{quote: "Using Rails with Postgres", strength: "stated"}]
      }

      formatted = described_class.format_concept_fact(result)

      expect(formatted[:id]).to eq(5)
      expect(formatted[:subject]).to eq("app")
      expect(formatted[:average_similarity]).to eq(0.88)
      expect(formatted[:concept_similarities]).to eq({"Rails" => 0.9, "Postgres" => 0.86})
      expect(formatted[:receipts].length).to eq(1)
    end
  end

  describe ".format_shortcut_results" do
    it "formats shortcut query results" do
      results = [
        {
          fact: {id: 5, subject_name: "app", predicate: "convention", object_literal: "Use TDD", scope: "global"},
          source: :global
        }
      ]

      formatted = described_class.format_shortcut_results("conventions", results)

      expect(formatted[:category]).to eq("conventions")
      expect(formatted[:count]).to eq(1)
      expect(formatted[:facts][0][:id]).to eq(5)
    end
  end

  describe ".format_shortcut_fact" do
    it "formats fact for shortcut queries without status" do
      result = {
        fact: {id: 20, subject_name: "repo", predicate: "decision", object_literal: "Use Postgres", scope: "project"},
        source: :project
      }

      formatted = described_class.format_shortcut_fact(result)

      expect(formatted[:id]).to eq(20)
      expect(formatted[:subject]).to eq("repo")
      expect(formatted[:predicate]).to eq("decision")
      expect(formatted[:object]).to eq("Use Postgres")
      expect(formatted[:scope]).to eq("project")
      expect(formatted[:source]).to eq(:project)
      expect(formatted).not_to have_key(:status)
      expect(formatted).not_to have_key(:receipts)
    end
  end

  describe ".format_tool_facts" do
    it "formats facts_by_tool query results" do
      results = [
        {
          fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", scope: "project"},
          source: :project,
          receipts: [{quote: "Used Read tool", strength: "stated"}]
        }
      ]

      formatted = described_class.format_tool_facts("Read", "all", results)

      expect(formatted[:tool_name]).to eq("Read")
      expect(formatted[:scope]).to eq("all")
      expect(formatted[:count]).to eq(1)
      expect(formatted[:facts][0][:id]).to eq(1)
      expect(formatted[:facts][0][:receipts].length).to eq(1)
    end

    it "handles empty results" do
      formatted = described_class.format_tool_facts("Grep", "project", [])

      expect(formatted[:count]).to eq(0)
      expect(formatted[:facts]).to eq([])
    end
  end

  describe ".format_context_facts" do
    it "formats facts_by_context query results" do
      results = [
        {
          fact: {id: 5, subject_name: "app", predicate: "convention", object_literal: "Use TDD", scope: "global"},
          source: :global,
          receipts: []
        }
      ]

      formatted = described_class.format_context_facts("git_branch", "main", "all", results)

      expect(formatted[:context_type]).to eq("git_branch")
      expect(formatted[:context_value]).to eq("main")
      expect(formatted[:scope]).to eq("all")
      expect(formatted[:count]).to eq(1)
      expect(formatted[:facts][0][:id]).to eq(5)
    end

    it "handles cwd context type" do
      results = []

      formatted = described_class.format_context_facts("cwd", "/home/user/project", "project", results)

      expect(formatted[:context_type]).to eq("cwd")
      expect(formatted[:context_value]).to eq("/home/user/project")
      expect(formatted[:count]).to eq(0)
    end
  end

  describe ".format_generic_fact" do
    it "formats fact with scope and receipts" do
      result = {
        fact: {id: 10, subject_name: "repo", predicate: "uses_framework", object_literal: "Rails", scope: "project"},
        source: :project,
        receipts: [
          {quote: "Using Rails", strength: "stated"},
          {quote: "Rails app", strength: "inferred"}
        ]
      }

      formatted = described_class.format_generic_fact(result)

      expect(formatted[:id]).to eq(10)
      expect(formatted[:subject]).to eq("repo")
      expect(formatted[:predicate]).to eq("uses_framework")
      expect(formatted[:object]).to eq("Rails")
      expect(formatted[:scope]).to eq("project")
      expect(formatted[:source]).to eq(:project)
      expect(formatted[:receipts].length).to eq(2)
      expect(formatted[:receipts][0][:quote]).to eq("Using Rails")
    end

    it "handles empty receipts" do
      result = {
        fact: {id: 1, subject_name: "repo", predicate: "uses", object_literal: "Ruby", scope: "global"},
        source: :global,
        receipts: []
      }

      formatted = described_class.format_generic_fact(result)

      expect(formatted[:receipts]).to eq([])
    end
  end
end
