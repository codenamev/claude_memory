# frozen_string_literal: true

require_relative "simple_acceptance_criteria"

RSpec.describe EvalHelpers::SimpleAcceptanceCriteria do
  describe "#evaluate" do
    let(:criteria) do
      described_class.new(
        required_keywords: ["Sequel", "dataset", "transaction"],
        threshold: 0.75
      )
    end

    it "returns passing evaluation when all keywords present" do
      response = "Use Sequel datasets with db[:users] and wrap in a transaction."

      evaluation = criteria.evaluate(response)

      expect(evaluation.passed?).to be(true)
      expect(evaluation.score).to eq(1.0)
      expect(evaluation.matched).to contain_exactly("Sequel", "dataset", "transaction")
      expect(evaluation.missing).to be_empty
    end

    it "returns failing evaluation when threshold not met" do
      response = "Use Sequel datasets with db[:users]."

      evaluation = criteria.evaluate(response)

      expect(evaluation.passed?).to be(false)
      expect(evaluation.score).to eq(2.0 / 3.0)
      expect(evaluation.matched).to contain_exactly("Sequel", "dataset")
      expect(evaluation.missing).to contain_exactly("transaction")
    end

    it "returns passing evaluation when threshold exactly met" do
      lenient_criteria = described_class.new(
        required_keywords: ["alpha", "beta", "gamma"],
        threshold: 0.66
      )

      response = "Contains alpha and beta but not the other one."

      evaluation = lenient_criteria.evaluate(response)

      expect(evaluation.passed?).to be(true)
      expect(evaluation.score).to be_within(0.01).of(0.67)
    end

    it "returns failing evaluation when below threshold" do
      response = "Use Sequel for database access."

      evaluation = criteria.evaluate(response)

      expect(evaluation.passed?).to be(false)
      expect(evaluation.score).to eq(0.33).or eq(1.0 / 3.0)
      expect(evaluation.matched).to contain_exactly("Sequel")
      expect(evaluation.missing).to contain_exactly("dataset", "transaction")
    end

    it "is case-insensitive" do
      response = "Use SEQUEL datasets with TRANSACTION support."

      evaluation = criteria.evaluate(response)

      expect(evaluation.passed?).to be(true)
      expect(evaluation.score).to eq(1.0)
    end

    it "matches partial words" do
      response = "Use Sequel datasets with transactional safety."

      evaluation = criteria.evaluate(response)

      expect(evaluation.passed?).to be(true)
      expect(evaluation.matched).to include("transaction")
    end

    it "respects custom threshold" do
      strict_criteria = described_class.new(
        required_keywords: ["one", "two", "three"],
        threshold: 0.90
      )

      # 2/3 = 0.67 < 0.90
      response = "Contains one and two but not the third."

      evaluation = strict_criteria.evaluate(response)

      expect(evaluation.passed?).to be(false)
      expect(evaluation.score).to eq(0.67).or eq(2.0 / 3.0)
    end
  end
end

RSpec.describe EvalHelpers::Evaluation do
  describe "#passed?" do
    it "returns true when score meets threshold" do
      evaluation = described_class.new(
        score: 0.80,
        threshold: 0.75,
        matched: ["one", "two"],
        missing: ["three"]
      )

      expect(evaluation.passed?).to be(true)
    end

    it "returns false when score below threshold" do
      evaluation = described_class.new(
        score: 0.60,
        threshold: 0.75,
        matched: ["one"],
        missing: ["two", "three"]
      )

      expect(evaluation.passed?).to be(false)
    end
  end

  describe "#details" do
    it "returns hash with evaluation details" do
      evaluation = described_class.new(
        score: 0.67,
        threshold: 0.75,
        matched: ["one", "two"],
        missing: ["three"]
      )

      details = evaluation.details

      expect(details[:passed]).to be(false)
      expect(details[:score]).to eq(0.67)
      expect(details[:threshold]).to eq(0.75)
      expect(details[:matched_keywords]).to eq(["one", "two"])
      expect(details[:missing_keywords]).to eq(["three"])
    end
  end
end
