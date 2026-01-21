# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Infrastructure::InMemoryFileSystem do
  let(:fs) { described_class.new }

  describe "#exist?" do
    it "returns false for non-existent file" do
      expect(fs.exist?("/tmp/missing.txt")).to be false
    end

    it "returns true after writing file" do
      fs.write("/tmp/test.txt", "content")
      expect(fs.exist?("/tmp/test.txt")).to be true
    end
  end

  describe "#read" do
    it "reads written content" do
      fs.write("/tmp/test.txt", "Hello!")
      expect(fs.read("/tmp/test.txt")).to eq("Hello!")
    end

    it "raises error for non-existent file" do
      expect { fs.read("/tmp/missing.txt") }.to raise_error(Errno::ENOENT, /missing.txt/)
    end
  end

  describe "#write" do
    it "stores content in memory" do
      fs.write("/tmp/test.txt", "content")
      expect(fs.read("/tmp/test.txt")).to eq("content")
    end

    it "overwrites existing content" do
      fs.write("/tmp/test.txt", "old")
      fs.write("/tmp/test.txt", "new")
      expect(fs.read("/tmp/test.txt")).to eq("new")
    end

    it "handles nested paths" do
      fs.write("/tmp/subdir/test.txt", "content")
      expect(fs.exist?("/tmp/subdir/test.txt")).to be true
    end
  end

  describe "#file_hash" do
    it "returns SHA256 hash of content" do
      fs.write("/tmp/test.txt", "test content")
      expected_hash = Digest::SHA256.hexdigest("test content")
      expect(fs.file_hash("/tmp/test.txt")).to eq(expected_hash)
    end

    it "returns different hashes for different content" do
      fs.write("/tmp/test1.txt", "content1")
      fs.write("/tmp/test2.txt", "content2")
      expect(fs.file_hash("/tmp/test1.txt")).not_to eq(fs.file_hash("/tmp/test2.txt"))
    end

    it "raises error for non-existent file" do
      expect { fs.file_hash("/tmp/missing.txt") }.to raise_error(Errno::ENOENT)
    end
  end

  describe "isolation" do
    it "does not affect real filesystem" do
      fs.write("/tmp/in_memory_test.txt", "content")
      expect(File.exist?("/tmp/in_memory_test.txt")).to be false
    end

    it "multiple instances are isolated" do
      fs1 = described_class.new
      fs2 = described_class.new

      fs1.write("/tmp/test.txt", "content1")
      fs2.write("/tmp/test.txt", "content2")

      expect(fs1.read("/tmp/test.txt")).to eq("content1")
      expect(fs2.read("/tmp/test.txt")).to eq("content2")
    end
  end
end
