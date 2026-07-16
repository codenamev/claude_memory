# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Distill::TruncationDetector do
  subject(:detector) { described_class.new }

  describe "#truncated?" do
    it "flags the '[Read output capped at N lines]' marker" do
      expect(detector.truncated?("...code...\n[Read output capped at 500 lines]")).to be true
    end

    it "flags a '[Truncated: N chars]' marker" do
      expect(detector.truncated?("blob\n[Truncated: 12000 chars]")).to be true
    end

    it "flags 'output was truncated' prose" do
      expect(detector.truncated?("The tool output was truncated for length.")).to be true
    end

    it "flags 'N lines omitted' / 'N characters truncated' markers" do
      expect(detector.truncated?("... 1,234 lines omitted ...")).to be true
      expect(detector.truncated?("(9000 characters truncated)")).to be true
    end

    it "is case-insensitive on the marker text" do
      expect(detector.truncated?("[read OUTPUT capped at 10 lines]")).to be true
    end

    it "returns false for complete content with no marker" do
      expect(detector.truncated?("def foo\n  bar\nend")).to be false
    end

    it "returns false for nil and empty input" do
      expect(detector.truncated?(nil)).to be false
      expect(detector.truncated?("")).to be false
    end

    it "does not fire on innocuous prose that merely mentions truncation elsewhere" do
      # No bracketed marker, no "output truncated" phrasing, no count-based form.
      expect(detector.truncated?("We should truncate long strings before hashing.")).to be false
    end
  end
end
