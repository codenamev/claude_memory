# frozen_string_literal: true

require "spec_helper"
require "claude_memory/mcp/text_summary"

RSpec.describe ClaudeMemory::MCP::TextSummary do
  describe ".for_tool" do
    it "returns error message when result has error key" do
      result = {error: "Something failed"}
      expect(described_class.for_tool("memory.recall", result)).to eq("Something failed")
    end

    it "falls back to JSON for unknown tools" do
      result = {foo: "bar"}
      expect(described_class.for_tool("unknown.tool", result)).to eq('{"foo":"bar"}')
    end
  end

  describe ".summarize_recall" do
    it "summarizes recall results" do
      result = {
        facts: [
          {id: 1, subject: "repo", predicate: "uses", object: "Ruby"}
        ]
      }
      summary = described_class.summarize_recall(result)

      expect(summary).to include("Found 1 fact(s):")
      expect(summary).to include("[1] repo.uses = Ruby")
    end

    it "handles empty results" do
      expect(described_class.summarize_recall({facts: []})).to eq("No facts found.")
    end
  end

  describe ".summarize_recall_index" do
    it "summarizes index results with token counts" do
      result = {
        query: "Ruby",
        result_count: 1,
        total_estimated_tokens: 50,
        facts: [{id: 1, subject: "repo", predicate: "uses", object_preview: "Ruby 3.2...", tokens: 50}]
      }
      summary = described_class.summarize_recall_index(result)

      expect(summary).to include("1 fact(s) matching 'Ruby'")
      expect(summary).to include("~50 tokens")
      expect(summary).to include("(50t)")
    end

    it "handles empty results" do
      result = {query: "nothing", facts: []}
      expect(described_class.summarize_recall_index(result)).to include("No matching facts")
    end
  end

  describe ".summarize_explain" do
    it "summarizes explanation with evidence" do
      result = {
        fact: {id: 5, subject: "repo", predicate: "uses", object: "Ruby", status: "active",
               valid_from: "2026-01-01", valid_from_ago: "32d ago"},
        source: "project",
        receipts: [{quote: "We use Ruby"}]
      }
      summary = described_class.summarize_explain(result)

      expect(summary).to include("Fact [5]: repo.uses = Ruby")
      expect(summary).to include("32d ago")
      expect(summary).to include("Evidence: We use Ruby")
    end
  end

  describe ".summarize_changes" do
    it "summarizes changes with relative time" do
      result = {
        since: "2026-01-01",
        changes: [
          {id: 1, predicate: "uses", object: "Ruby", status: "active", created_ago: "2h ago"}
        ]
      }
      summary = described_class.summarize_changes(result)

      expect(summary).to include("1 change(s) since 2026-01-01")
      expect(summary).to include("(2h ago)")
    end

    it "handles empty changes" do
      result = {since: "2026-01-01", changes: []}
      expect(described_class.summarize_changes(result)).to include("No changes since")
    end
  end

  describe ".summarize_conflicts" do
    it "summarizes conflicts" do
      result = {
        count: 1,
        conflicts: [{id: 10, fact_a: 1, fact_b: 2, status: "open"}]
      }
      summary = described_class.summarize_conflicts(result)

      expect(summary).to include("1 conflict(s)")
      expect(summary).to include("fact 1 vs fact 2")
    end

    it "handles no conflicts" do
      expect(described_class.summarize_conflicts({count: 0})).to eq("No open conflicts.")
    end
  end

  describe ".summarize_sweep" do
    it "summarizes sweep statistics" do
      result = {scope: "project", proposed_expired: 2, disputed_expired: 1,
                orphaned_deleted: 3, content_pruned: 0, elapsed_seconds: 1.5}
      summary = described_class.summarize_sweep(result)

      expect(summary).to include("Sweep (project)")
      expect(summary).to include("2 proposed expired")
      expect(summary).to include("1.5s")
    end
  end

  describe ".summarize_shortcut" do
    it "summarizes shortcut results" do
      result = {
        category: "decisions",
        count: 1,
        facts: [{id: 5, object: "Use PostgreSQL"}]
      }
      summary = described_class.summarize_shortcut(result)

      expect(summary).to include("1 decisions:")
      expect(summary).to include("[5] Use PostgreSQL")
    end

    it "handles empty results" do
      result = {category: "conventions", count: 0, facts: []}
      expect(described_class.summarize_shortcut(result)).to include("No conventions found")
    end
  end

  describe ".summarize_semantic" do
    it "summarizes semantic results with similarity" do
      result = {
        query: "database",
        mode: "both",
        count: 1,
        facts: [{id: 1, subject: "repo", predicate: "uses", object: "PostgreSQL", similarity: 0.95}]
      }
      summary = described_class.summarize_semantic(result)

      expect(summary).to include("1 match(es)")
      expect(summary).to include("(95%)")
    end
  end

  describe ".summarize_concepts" do
    it "summarizes concept results" do
      result = {
        concepts: ["auth", "JWT"],
        count: 1,
        facts: [{id: 1, subject: "api", predicate: "uses", object: "JWT auth", average_similarity: 0.88}]
      }
      summary = described_class.summarize_concepts(result)

      expect(summary).to include("auth + JWT")
      expect(summary).to include("(88%)")
    end
  end

  describe ".summarize_promote" do
    it "summarizes successful promotion" do
      result = {success: true, project_fact_id: 5, global_fact_id: 42}
      summary = described_class.summarize_promote(result)

      expect(summary).to include("Fact 5 promoted to global")
      expect(summary).to include("new ID: 42")
    end
  end

  describe ".summarize_extraction" do
    it "summarizes successful extraction" do
      result = {success: true, facts_created: 3, entities_created: 2,
                facts_superseded: 1, conflicts_created: 0}
      summary = described_class.summarize_extraction(result)

      expect(summary).to include("3 facts")
      expect(summary).to include("2 entities")
    end
  end

  describe ".summarize_check_setup" do
    it "summarizes setup status" do
      result = {
        status: "ok",
        version: {current: "0.4.0", latest: "0.4.0"},
        components: {global_database: true, project_database: true, hooks_configured: true},
        issues: [],
        warnings: []
      }
      summary = described_class.summarize_check_setup(result)

      expect(summary).to include("Setup status: ok")
      expect(summary).to include("0.4.0")
    end
  end
end
