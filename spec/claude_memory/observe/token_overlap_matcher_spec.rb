# frozen_string_literal: true

RSpec.describe ClaudeMemory::Observe::TokenOverlapMatcher do
  subject(:matcher) { described_class.new }

  it "treats identical bodies as similar" do
    expect(matcher.similar?("decided to use SQLite", "decided to use SQLite")).to be true
  end

  it "folds near-duplicate wording of the same event" do
    # Jaccard 0.6 ({precompact,hook,set} vs +{design,analog})
    expect(matcher.similar?("PreCompact hook set.", "PreCompact hook set — the design analog")).to be true
  end

  it "keeps unrelated statements apart" do
    expect(matcher.similar?("decided to use SQLite for storage", "always run rubocop before commit")).to be false
  end

  it "ignores stopwords, case, and whitespace" do
    expect(matcher.similar?("We decided to SHIP the   feature", "decided to ship the feature")).to be true
  end

  it "returns false for empty or stopword-only bodies" do
    expect(matcher.similar?("", "anything goes here")).to be false
    expect(matcher.similar?("to the of and", "or but with as")).to be false
  end

  it "honors a custom threshold" do
    strict = described_class.new(threshold: 0.95)
    expect(strict.similar?("PreCompact hook set.", "PreCompact hook set — the design analog")).to be false
  end

  it "does not capture pure synonym paraphrases (documented limitation)" do
    # "use SQLite" / "chose SQLite" share only one content word — no free
    # lexical method folds this; a semantic matcher would. See class docs.
    expect(matcher.similar?("decided to use SQLite", "we chose SQLite as the database")).to be false
  end
end
