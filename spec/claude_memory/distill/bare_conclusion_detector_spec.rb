# frozen_string_literal: true

RSpec.describe ClaudeMemory::Distill::BareConclusionDetector do
  let(:detector) { described_class.new }

  describe "#bare_conclusion?" do
    context "when predicate is decision or convention" do
      it "returns true for a bare decision with no reason clause" do
        fact = {predicate: "decision", object_literal: "We chose SQLite for storage"}
        expect(detector.bare_conclusion?(fact)).to be true
      end

      it "returns true for a bare convention" do
        fact = {predicate: "convention", object_literal: "Use 4-space indentation"}
        expect(detector.bare_conclusion?(fact)).to be true
      end

      it "returns false when the object embeds 'because'" do
        fact = {predicate: "convention",
                object_literal: "Use frozen_string_literal because mutations cause subtle bugs"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false when the object embeds 'so that'" do
        fact = {predicate: "decision",
                object_literal: "Adopt sqlite-vec so that semantic recall stays in-process"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false when the object embeds 'to avoid'" do
        fact = {predicate: "convention",
                object_literal: "Always close stores explicitly to avoid WAL leaks"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false when the object embeds 'caused by'" do
        fact = {predicate: "decision",
                object_literal: "Pin extralite version, drift caused by unrelated SQLite upgrades"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false when the object embeds 'in order to'" do
        fact = {predicate: "decision",
                object_literal: "Run sweep on PreCompact in order to keep DB lean before context window resets"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "matches case-insensitively" do
        fact = {predicate: "convention", object_literal: "Be careful BECAUSE state matters"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "accepts the :object key as a fallback shape" do
        fact = {predicate: "convention", object: "Use tabs"}
        expect(detector.bare_conclusion?(fact)).to be true
      end
    end

    context "for predicates that are not guarded" do
      it "returns false for uses_database (carries meaning in shape)" do
        fact = {predicate: "uses_database", object_literal: "sqlite"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false for uses_framework even when object is bare" do
        fact = {predicate: "uses_framework", object_literal: "rails"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false for architecture facts" do
        fact = {predicate: "architecture", object_literal: "PredicatePolicy is single source of truth"}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false for the reference predicate" do
        fact = {predicate: "reference", object_literal: "Some external library, 5000 stars"}
        expect(detector.bare_conclusion?(fact)).to be false
      end
    end

    context "edge cases" do
      it "returns false for an empty object" do
        fact = {predicate: "decision", object_literal: ""}
        expect(detector.bare_conclusion?(fact)).to be false
      end

      it "returns false for a nil object" do
        fact = {predicate: "convention", object_literal: nil}
        expect(detector.bare_conclusion?(fact)).to be false
      end
    end
  end
end
