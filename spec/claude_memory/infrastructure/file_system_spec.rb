# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe ClaudeMemory::Infrastructure::FileSystem do
  let(:fs) { described_class.new }
  let(:test_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(test_dir) }

  describe "#exist?" do
    it "returns true for existing file" do
      path = File.join(test_dir, "test.txt")
      File.write(path, "content")
      expect(fs.exist?(path)).to be true
    end

    it "returns false for non-existent file" do
      path = File.join(test_dir, "missing.txt")
      expect(fs.exist?(path)).to be false
    end
  end

  describe "#read" do
    it "reads file content" do
      path = File.join(test_dir, "test.txt")
      File.write(path, "Hello, World!")
      expect(fs.read(path)).to eq("Hello, World!")
    end

    it "raises error for non-existent file" do
      path = File.join(test_dir, "missing.txt")
      expect { fs.read(path) }.to raise_error(Errno::ENOENT)
    end
  end

  describe "#write" do
    it "writes content to file" do
      path = File.join(test_dir, "test.txt")
      fs.write(path, "content")
      expect(File.read(path)).to eq("content")
    end

    it "creates parent directories if needed" do
      path = File.join(test_dir, "subdir", "test.txt")
      fs.write(path, "content")
      expect(File.exist?(path)).to be true
      expect(File.read(path)).to eq("content")
    end

    it "overwrites existing file" do
      path = File.join(test_dir, "test.txt")
      File.write(path, "old")
      fs.write(path, "new")
      expect(File.read(path)).to eq("new")
    end
  end

  describe "#file_hash" do
    it "returns SHA256 hash of file content" do
      path = File.join(test_dir, "test.txt")
      File.write(path, "test content")
      expected_hash = Digest::SHA256.hexdigest("test content")
      expect(fs.file_hash(path)).to eq(expected_hash)
    end

    it "returns different hashes for different content" do
      path1 = File.join(test_dir, "test1.txt")
      path2 = File.join(test_dir, "test2.txt")
      File.write(path1, "content1")
      File.write(path2, "content2")
      expect(fs.file_hash(path1)).not_to eq(fs.file_hash(path2))
    end
  end
end
