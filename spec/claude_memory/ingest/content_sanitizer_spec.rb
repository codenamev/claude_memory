# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Ingest::ContentSanitizer do
  describe "::SYSTEM_TAGS" do
    it "includes claude-memory-context" do
      expect(described_class::SYSTEM_TAGS).to include("claude-memory-context")
    end
  end

  describe "::USER_TAGS" do
    it "includes privacy tags" do
      expect(described_class::USER_TAGS).to include("private", "no-memory", "secret")
    end
  end

  describe "::MAX_TAG_COUNT" do
    it "defines ReDoS protection limit" do
      expect(described_class::MAX_TAG_COUNT).to eq(100)
    end
  end

  describe ".strip_tags" do
    it "strips private tags and content" do
      text = "Public <private>Secret</private> Public"
      result = described_class.strip_tags(text)

      expect(result).to eq("Public  Public")
      expect(result).not_to include("Secret")
    end

    it "strips multiple tag types" do
      text = "A <private>X</private> B <no-memory>Y</no-memory> C"
      result = described_class.strip_tags(text)

      expect(result).to eq("A  B  C")
    end

    it "strips secret tags" do
      text = "Public <secret>API key</secret> data"
      result = described_class.strip_tags(text)

      expect(result).to eq("Public  data")
    end

    it "strips claude-memory-context system tags" do
      text = "Before <claude-memory-context>Context</claude-memory-context> After"
      result = described_class.strip_tags(text)

      expect(result).to eq("Before  After")
    end

    it "handles multiline content" do
      text = "Line1\n<private>Line2\nLine3</private>\nLine4"
      result = described_class.strip_tags(text)

      expect(result).to eq("Line1\n\nLine4")
    end

    it "preserves text without tags" do
      text = "No privacy tags here"
      result = described_class.strip_tags(text)

      expect(result).to eq("No privacy tags here")
    end

    it "raises error when tag count exceeds limit" do
      text = "<private>x</private>" * 101

      expect {
        described_class.strip_tags(text)
      }.to raise_error(ClaudeMemory::Error, /Too many privacy tags/)
    end

    it "allows reasonable tag counts" do
      text = "<private>x</private>" * 50

      expect {
        described_class.strip_tags(text)
      }.not_to raise_error
    end

    it "does not mutate original text" do
      text = "Public <private>Secret</private> data"
      original = text.dup

      described_class.strip_tags(text)
      expect(text).to eq(original)
    end
  end
end

RSpec.describe ClaudeMemory::Ingest::ContentSanitizer::Pure do
  describe ".all_tags" do
    it "returns all tag objects" do
      tags = described_class.all_tags

      expect(tags).to all(be_a(ClaudeMemory::Ingest::PrivacyTag))
      expect(tags.size).to be >= 4
    end

    it "includes system and user tags" do
      tags = described_class.all_tags
      tag_names = tags.map(&:name)

      expect(tag_names).to include("claude-memory-context")
      expect(tag_names).to include("private")
      expect(tag_names).to include("no-memory")
      expect(tag_names).to include("secret")
    end
  end

  describe ".strip_tags" do
    it "strips tags from text using tag objects" do
      tags = [ClaudeMemory::Ingest::PrivacyTag.new("private")]
      text = "Public <private>Secret</private> Public"

      result = described_class.strip_tags(text, tags)
      expect(result).to eq("Public  Public")
    end

    it "applies all tags in sequence" do
      tags = [
        ClaudeMemory::Ingest::PrivacyTag.new("private"),
        ClaudeMemory::Ingest::PrivacyTag.new("secret")
      ]
      text = "A <private>X</private> B <secret>Y</secret> C"

      result = described_class.strip_tags(text, tags)
      expect(result).to eq("A  B  C")
    end

    it "does not mutate input text" do
      tags = [ClaudeMemory::Ingest::PrivacyTag.new("private")]
      text = "Public <private>Secret</private> data"
      original = text.dup

      described_class.strip_tags(text, tags)
      expect(text).to eq(original)
    end

    it "returns original text if no tags match" do
      tags = [ClaudeMemory::Ingest::PrivacyTag.new("private")]
      text = "No tags here"

      result = described_class.strip_tags(text, tags)
      expect(result).to eq(text)
    end

    it "handles empty tag list" do
      text = "Some <private>content</private> here"

      result = described_class.strip_tags(text, [])
      expect(result).to eq(text)
    end
  end

  describe ".count_tags" do
    it "counts tag occurrences in text" do
      tags = [ClaudeMemory::Ingest::PrivacyTag.new("private")]
      text = "<private>A</private> and <private>B</private>"

      count = described_class.count_tags(text, tags)
      expect(count).to eq(2)
    end

    it "counts across multiple tag types" do
      tags = [
        ClaudeMemory::Ingest::PrivacyTag.new("private"),
        ClaudeMemory::Ingest::PrivacyTag.new("secret")
      ]
      text = "<private>A</private> and <secret>B</secret> and <private>C</private>"

      count = described_class.count_tags(text, tags)
      expect(count).to eq(3)
    end

    it "returns zero for text without tags" do
      tags = [ClaudeMemory::Ingest::PrivacyTag.new("private")]
      text = "No tags here"

      count = described_class.count_tags(text, tags)
      expect(count).to eq(0)
    end

    it "only counts opening tags" do
      tags = [ClaudeMemory::Ingest::PrivacyTag.new("private")]
      text = "<private>content</private>"

      count = described_class.count_tags(text, tags)
      expect(count).to eq(1) # Only counts opening tag
    end
  end
end
