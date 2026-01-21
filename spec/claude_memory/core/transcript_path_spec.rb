# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::TranscriptPath do
  describe "#initialize" do
    it "accepts a string path" do
      path = described_class.new("/tmp/transcript.jsonl")
      expect(path.value).to eq("/tmp/transcript.jsonl")
    end

    it "converts non-string values to strings" do
      path = described_class.new(Pathname.new("/tmp/file.txt"))
      expect(path.value).to eq("/tmp/file.txt")
    end

    it "raises error for empty string" do
      expect { described_class.new("") }.to raise_error(ArgumentError, "Transcript path cannot be empty")
    end

    it "raises error for nil" do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, "Transcript path cannot be empty")
    end

    it "freezes the object" do
      path = described_class.new("/tmp/test.jsonl")
      expect(path).to be_frozen
    end

    it "accepts relative paths" do
      path = described_class.new("./local/transcript.jsonl")
      expect(path.value).to eq("./local/transcript.jsonl")
    end

    it "accepts absolute paths" do
      path = described_class.new("/absolute/path/transcript.jsonl")
      expect(path.value).to eq("/absolute/path/transcript.jsonl")
    end
  end

  describe "#to_s" do
    it "returns the string path" do
      path = described_class.new("/tmp/transcript.jsonl")
      expect(path.to_s).to eq("/tmp/transcript.jsonl")
    end
  end

  describe "#==" do
    it "returns true for same path" do
      path1 = described_class.new("/tmp/test.jsonl")
      path2 = described_class.new("/tmp/test.jsonl")
      expect(path1).to eq(path2)
    end

    it "returns false for different paths" do
      path1 = described_class.new("/tmp/test1.jsonl")
      path2 = described_class.new("/tmp/test2.jsonl")
      expect(path1).not_to eq(path2)
    end

    it "returns false for different types" do
      path = described_class.new("/tmp/test.jsonl")
      expect(path).not_to eq("/tmp/test.jsonl")
    end
  end

  describe "#eql?" do
    it "behaves like ==" do
      path1 = described_class.new("/tmp/test.jsonl")
      path2 = described_class.new("/tmp/test.jsonl")
      expect(path1.eql?(path2)).to be true
    end
  end

  describe "#hash" do
    it "returns same hash for equal paths" do
      path1 = described_class.new("/tmp/test.jsonl")
      path2 = described_class.new("/tmp/test.jsonl")
      expect(path1.hash).to eq(path2.hash)
    end

    it "can be used as hash key" do
      path1 = described_class.new("/tmp/test.jsonl")
      path2 = described_class.new("/tmp/test.jsonl")
      hash = {path1 => "value"}
      expect(hash[path2]).to eq("value")
    end
  end
end
