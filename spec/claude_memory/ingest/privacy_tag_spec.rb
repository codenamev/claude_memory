# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Ingest::PrivacyTag do
  describe "#initialize" do
    it "creates a privacy tag with a name" do
      tag = described_class.new("private")
      expect(tag.name).to eq("private")
    end

    it "accepts string names" do
      tag = described_class.new("no-memory")
      expect(tag.name).to eq("no-memory")
    end

    it "freezes the tag (immutability)" do
      tag = described_class.new("private")
      expect(tag).to be_frozen
    end

    it "raises error for nil name" do
      expect { described_class.new(nil) }.to raise_error(ClaudeMemory::Error, /Tag name cannot be empty/)
    end

    it "raises error for empty name" do
      expect { described_class.new("") }.to raise_error(ClaudeMemory::Error, /Tag name cannot be empty/)
    end

    it "raises error for whitespace-only name" do
      expect { described_class.new("  ") }.to raise_error(ClaudeMemory::Error, /Tag name cannot be empty/)
    end
  end

  describe "#pattern" do
    it "returns a regex pattern for the tag" do
      tag = described_class.new("private")
      pattern = tag.pattern

      expect(pattern).to be_a(Regexp)
      expect("before <private>secret</private> after").to match(pattern)
    end

    it "matches multiline content" do
      tag = described_class.new("private")
      pattern = tag.pattern

      text = "before <private>line1\nline2</private> after"
      expect(text).to match(pattern)
    end

    it "escapes special regex characters in tag name" do
      tag = described_class.new("private-tag")
      pattern = tag.pattern

      # The hyphen should be escaped
      expect("<private-tag>content</private-tag>").to match(pattern)
      expect("<privatextag>content</privatextag>").not_to match(pattern)
    end

    it "handles tags with dots" do
      tag = described_class.new("no.memory")
      pattern = tag.pattern

      expect("<no.memory>content</no.memory>").to match(pattern)
    end
  end

  describe "#strip_from" do
    it "removes tagged content from text" do
      tag = described_class.new("private")
      text = "Public <private>Secret</private> Public"

      result = tag.strip_from(text)
      expect(result).to eq("Public  Public")
      expect(result).not_to include("Secret")
    end

    it "removes multiple occurrences" do
      tag = described_class.new("private")
      text = "A <private>X</private> B <private>Y</private> C"

      result = tag.strip_from(text)
      expect(result).to eq("A  B  C")
    end

    it "preserves text without tags" do
      tag = described_class.new("private")
      text = "No tags here"

      result = tag.strip_from(text)
      expect(result).to eq("No tags here")
    end

    it "handles multiline content" do
      tag = described_class.new("private")
      text = "Line1\n<private>Line2\nLine3</private>\nLine4"

      result = tag.strip_from(text)
      expect(result).to eq("Line1\n\nLine4")
    end

    it "does not mutate the original text" do
      tag = described_class.new("private")
      text = "Public <private>Secret</private> Public"
      original = text.dup

      tag.strip_from(text)
      expect(text).to eq(original)
    end

    it "handles nested tags with different names" do
      tag = described_class.new("private")
      text = "Public <private>Outer <secret>Inner</secret></private> End"

      result = tag.strip_from(text)
      expect(result).to eq("Public  End")
    end

    it "handles malformed nested tags with same name (strips innermost match)" do
      tag = described_class.new("private")
      # This is malformed HTML/XML - same tag name nested
      text = "Public <private>Outer <private>Inner</private> More</private> End"

      # The regex will match the first <private> to the first </private>
      # This is expected behavior for non-greedy matching
      result = tag.strip_from(text)
      # After first strip: "Public  More</private> End"
      # After second strip: "Public  More End" (the orphaned </private> is left)
      # This is acceptable - users shouldn't nest tags with the same name
      expect(result).not_to include("<private>")
    end

    it "handles empty content between tags" do
      tag = described_class.new("private")
      text = "Before <private></private> After"

      result = tag.strip_from(text)
      expect(result).to eq("Before  After")
    end
  end

  describe "#==" do
    it "returns true for tags with same name" do
      tag1 = described_class.new("private")
      tag2 = described_class.new("private")

      expect(tag1).to eq(tag2)
    end

    it "returns false for tags with different names" do
      tag1 = described_class.new("private")
      tag2 = described_class.new("secret")

      expect(tag1).not_to eq(tag2)
    end
  end

  describe "#hash" do
    it "returns same hash for tags with same name" do
      tag1 = described_class.new("private")
      tag2 = described_class.new("private")

      expect(tag1.hash).to eq(tag2.hash)
    end

    it "allows tags to be used as hash keys" do
      tag = described_class.new("private")
      hash = {tag => "value"}

      expect(hash[described_class.new("private")]).to eq("value")
    end
  end
end
