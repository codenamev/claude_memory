# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Ingest::TranscriptReader do
  let(:transcript_path) { File.join(Dir.tmpdir, "transcript_test_#{Process.pid}.jsonl") }

  before { File.write(transcript_path, "") }
  after { FileUtils.rm_f(transcript_path) }

  describe ".read_delta" do
    it "returns nil and 0 offset for empty file" do
      delta, new_offset = described_class.read_delta(transcript_path, 0)
      expect(delta).to be_nil
      expect(new_offset).to eq(0)
    end

    it "reads entire content from offset 0" do
      File.write(transcript_path, "line1\nline2\n")
      delta, new_offset = described_class.read_delta(transcript_path, 0)
      expect(delta).to eq("line1\nline2\n")
      expect(new_offset).to eq(12)
    end

    it "reads only new content from offset" do
      File.write(transcript_path, "line1\nline2\n")
      delta, new_offset = described_class.read_delta(transcript_path, 6)
      expect(delta).to eq("line2\n")
      expect(new_offset).to eq(12)
    end

    it "returns nil when no new content" do
      File.write(transcript_path, "line1\n")
      delta, new_offset = described_class.read_delta(transcript_path, 6)
      expect(delta).to be_nil
      expect(new_offset).to eq(6)
    end

    it "resets offset to 0 if file shrinks" do
      File.write(transcript_path, "small")
      delta, new_offset = described_class.read_delta(transcript_path, 100)
      expect(delta).to eq("small")
      expect(new_offset).to eq(5)
    end

    it "handles non-existent file" do
      FileUtils.rm_f(transcript_path)
      expect { described_class.read_delta(transcript_path, 0) }
        .to raise_error(ClaudeMemory::Ingest::TranscriptReader::FileNotFoundError)
    end
  end
end
