# frozen_string_literal: true

RSpec.describe ClaudeMemory::Distill::ReferenceMaterialDetector do
  let(:detector) { described_class.new }

  describe "#reclassify" do
    it "reclassifies LOC-count descriptions of external plugins from convention to reference" do
      # Observed in production data: project fact labeled 'convention' with
      # the object literal "Cloud-backed Claude Code plugin (~1,195 LOC JavaScript)
      # using Supermemory API…". This is a description of an external thing,
      # not a convention the user applies.
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "convention",
           object: "Cloud-backed Claude Code plugin (~1,195 LOC JavaScript) using Supermemory API for persistent memory"}
        ]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.first[:predicate]).to eq("reference")
    end

    it "reclassifies star-count + author-attribution descriptions as reference" do
      # "Claude Code plugin with marketplace.json, skill definitions, MCP
      # server bundling. 5,700+ stars, by Tobi Lütke. Custom fine-tuned
      # query expansion." → clearly reference material, not a convention.
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "convention",
           object: "Claude Code plugin with marketplace.json and MCP server bundling. 5,700+ stars, by Tobi Lütke."}
        ]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.first[:predicate]).to eq("reference")
    end

    it "leaves legitimate conventions untouched" do
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "convention", object: "Prefer do...end over braces for multi-line blocks"},
          {subject: "repo", predicate: "convention", object: "Never use Sequel.sqlite; this gem depends only on extralite"},
          {subject: "repo", predicate: "convention", object: "Use frozen_string_literal: true at the top of Ruby files"}
        ]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.map { |f| f[:predicate] }).to all(eq("convention"))
    end

    it "leaves decisions and architecture predicates untouched even when they mention external projects" do
      # Only conventions get the guard — decisions about which tech to adopt
      # are legitimately decisions even when they cite an external project.
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "decision",
           object: "From QMD 2026-02-02 restudy: adopt Claude Code plugin format, MCP structured content pattern."}
        ]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.first[:predicate]).to eq("decision")
    end

    it "matches 'is a plugin/library/tool for…' template as reference" do
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "convention",
           object: "grepai is a library for semantic code search using local LLM + grep."}
        ]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.first[:predicate]).to eq("reference")
    end

    it "preserves all other fact fields while changing only predicate" do
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "convention", object: "Tool X has 10,000+ stars by Jane Doe.",
           quote: "source quote", strength: "stated", confidence: 0.9}
        ]
      )
      out = detector.reclassify(extraction)
      fact = out.facts.first
      expect(fact[:subject]).to eq("repo")
      expect(fact[:object]).to eq("Tool X has 10,000+ stars by Jane Doe.")
      expect(fact[:quote]).to eq("source quote")
      expect(fact[:strength]).to eq("stated")
      expect(fact[:confidence]).to eq(0.9)
    end

    it "returns the same Extraction when no facts match reference patterns" do
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [{subject: "repo", predicate: "convention", object: "Use trailing commas in multi-line arrays"}]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.first[:predicate]).to eq("convention")
    end

    it "handles empty extractions without error" do
      extraction = ClaudeMemory::Distill::Extraction.new(facts: [])
      expect { detector.reclassify(extraction) }.not_to raise_error
    end

    it "does not reclassify conventions that merely contain 'by Firstname Lastname' phrasing" do
      # Production data (fact #142 in the claude_memory project DB): a real
      # convention about refresh sequences contains "MCP launched by Claude
      # Code run from PATH". The `by Claude Code` substring looked like
      # author attribution, triggering a false positive. We now require
      # a co-occurring strong signal (LOC count, star count, "is a plugin"
      # descriptor) before reclassifying.
      extraction = ClaudeMemory::Distill::Extraction.new(
        facts: [
          {subject: "repo", predicate: "convention",
           object: "Four-surface staleness: hooks + MCP launched by Claude Code run from PATH — refresh all four."}
        ]
      )
      out = detector.reclassify(extraction)
      expect(out.facts.first[:predicate]).to eq("convention")
    end
  end
end
