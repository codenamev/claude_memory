# frozen_string_literal: true

module EvalHelpers
  class SimpleAcceptanceCriteria
    attr_reader :required_keywords, :threshold

    def initialize(required_keywords:, threshold: 0.75)
      @required_keywords = required_keywords
      @threshold = threshold
      freeze
    end

    def evaluate(response)
      matches = @required_keywords.select do |keyword|
        response.downcase.include?(keyword.downcase)
      end

      score = matches.size.to_f / @required_keywords.size

      Evaluation.new(
        score: score,
        threshold: @threshold,
        matched: matches,
        missing: @required_keywords - matches
      )
    end
  end

  class Evaluation
    attr_reader :score, :threshold, :matched, :missing

    def initialize(score:, threshold:, matched:, missing:)
      @score = score
      @threshold = threshold
      @matched = matched
      @missing = missing
      freeze
    end

    def passed?
      score >= threshold
    end

    def details
      {
        passed: passed?,
        score: score,
        threshold: threshold,
        matched_keywords: matched,
        missing_keywords: missing
      }
    end
  end
end
