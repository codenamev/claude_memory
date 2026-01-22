# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::TokenEstimator do
  describe ".estimate" do
    it "estimates tokens for short text" do
      result = described_class.estimate("hello world")
      expect(result).to eq(3) # ~11 chars / 4 = 2.75, rounded up to 3
    end

    it "estimates tokens for longer text" do
      text = "The quick brown fox jumps over the lazy dog"
      result = described_class.estimate(text)
      expect(result).to be_between(10, 12)
    end

    it "handles empty text" do
      expect(described_class.estimate("")).to eq(0)
    end

    it "handles nil text" do
      expect(described_class.estimate(nil)).to eq(0)
    end

    it "normalizes whitespace before counting" do
      text_with_extra_spaces = "a    b    c"
      normalized_text = "a b c"

      result1 = described_class.estimate(text_with_extra_spaces)
      result2 = described_class.estimate(normalized_text)

      expect(result1).to eq(result2)
    end

    it "strips leading and trailing whitespace" do
      text = "  hello world  "
      result = described_class.estimate(text)
      expect(result).to eq(3)
    end

    it "rounds up to avoid underestimation" do
      # 1 character should be at least 1 token
      result = described_class.estimate("a")
      expect(result).to eq(1)
    end

    it "estimates realistic token count for code" do
      code = <<~RUBY
        def hello
          puts "Hello, world!"
        end
      RUBY

      result = described_class.estimate(code)
      expect(result).to be > 5
      expect(result).to be < 15
    end

    it "estimates realistic token count for markdown" do
      markdown = <<~MD
        # Heading

        This is a paragraph with some **bold** text and *italic* text.

        - List item 1
        - List item 2
      MD

      result = described_class.estimate(markdown)
      expect(result).to be > 15
      expect(result).to be < 30
    end
  end

  describe ".estimate_fact" do
    it "estimates tokens for a fact record" do
      fact = {
        subject_name: "project",
        predicate: "uses_database",
        object_literal: "PostgreSQL"
      }

      result = described_class.estimate_fact(fact)
      expect(result).to be > 0
      expect(result).to be < 10
    end

    it "handles nil values in fact" do
      fact = {
        subject_name: "project",
        predicate: "uses_database",
        object_literal: nil
      }

      result = described_class.estimate_fact(fact)
      expect(result).to be > 0
    end

    it "estimates accurately for longer facts" do
      fact = {
        subject_name: "authentication_service",
        predicate: "implementation_detail",
        object_literal: "Uses JWT tokens with RS256 signing algorithm and 1-hour expiration"
      }

      result = described_class.estimate_fact(fact)
      expect(result).to be > 15
      expect(result).to be < 30
    end

    it "returns zero for completely nil fact" do
      fact = {
        subject_name: nil,
        predicate: nil,
        object_literal: nil
      }

      result = described_class.estimate_fact(fact)
      expect(result).to eq(0)
    end
  end
end
