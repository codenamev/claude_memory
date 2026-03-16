# frozen_string_literal: true

RSpec.describe ClaudeMemory::MCP::ErrorClassifier do
  describe ".classify" do
    it "classifies Errno::EACCES as retryable" do
      error = Errno::EACCES.new("permission denied")
      expect(described_class.classify(error)).to eq("retryable")
    end

    it "classifies Errno::EAGAIN as retryable" do
      error = Errno::EAGAIN.new("resource busy")
      expect(described_class.classify(error)).to eq("retryable")
    end

    it "classifies IOError as retryable" do
      error = IOError.new("stream closed")
      expect(described_class.classify(error)).to eq("retryable")
    end

    it "classifies Errno::ENOSPC as fatal" do
      error = Errno::ENOSPC.new("no space")
      expect(described_class.classify(error)).to eq("fatal")
    end

    it "classifies Errno::EROFS as fatal" do
      error = Errno::EROFS.new("read-only fs")
      expect(described_class.classify(error)).to eq("fatal")
    end

    it "classifies TypeError as fatal" do
      error = TypeError.new("wrong type")
      expect(described_class.classify(error)).to eq("fatal")
    end

    it "classifies ArgumentError as fatal" do
      error = ArgumentError.new("bad arg")
      expect(described_class.classify(error)).to eq("fatal")
    end

    it "classifies unknown errors as fatal" do
      error = RuntimeError.new("something unexpected")
      expect(described_class.classify(error)).to eq("fatal")
    end
  end

  describe ".build_error_response" do
    it "builds retryable response with retry flag" do
      error = IOError.new("connection reset")
      result = described_class.build_error_response(error, tool_name: "memory.recall")

      expect(result[:severity]).to eq("retryable")
      expect(result[:retry]).to be true
      expect(result[:tool]).to eq("memory.recall")
      expect(result[:error]).to eq("Temporary failure")
    end

    it "builds fatal response with recommendations" do
      error = Errno::ENOSPC.new("no space left")
      result = described_class.build_error_response(error, tool_name: "memory.store_extraction")

      expect(result[:severity]).to eq("fatal")
      expect(result[:retry]).to be false
      expect(result[:recommendations]).to include("Run memory.check_setup to diagnose the issue")
      expect(result[:recommendations]).to include("Free up disk space and retry")
    end

    it "includes corruption recommendations for corrupt database" do
      error = RuntimeError.new("database disk image is malformed")
      result = described_class.build_error_response(error)

      expect(result[:recommendations]).to include("Database may be corrupted — run: claude-memory doctor")
    end
  end

  describe ".build_benign_response" do
    it "builds no_results response" do
      result = described_class.build_benign_response(:no_results, tool_name: "memory.recall")

      expect(result[:severity]).to eq("benign")
      expect(result[:message]).to include("No matching facts")
      expect(result[:results]).to eq([])
    end

    it "builds not_initialized response" do
      result = described_class.build_benign_response(:not_initialized)

      expect(result[:severity]).to eq("benign")
      expect(result[:message]).to include("not yet initialized")
    end

    it "builds empty_database response" do
      result = described_class.build_benign_response(:empty_database)

      expect(result[:severity]).to eq("benign")
      expect(result[:message]).to include("contains no facts")
    end
  end
end
