# frozen_string_literal: true

require "json"
require "stringio"

RSpec.describe ClaudeMemory::Logging::Logger do
  let(:output) { StringIO.new }

  describe "#initialize" do
    it "defaults to WARN level" do
      logger = described_class.new(output: output)
      expect(logger.level).to eq(described_class::WARN)
    end

    it "accepts explicit level" do
      logger = described_class.new(output: output, level: :debug)
      expect(logger.level).to eq(described_class::DEBUG)
    end

    it "reads level from CLAUDE_MEMORY_LOG_LEVEL env var" do
      env_backup = ENV["CLAUDE_MEMORY_LOG_LEVEL"]
      begin
        ENV["CLAUDE_MEMORY_LOG_LEVEL"] = "info"
        logger = described_class.new(output: output)
        expect(logger.level).to eq(described_class::INFO)
      ensure
        if env_backup
          ENV["CLAUDE_MEMORY_LOG_LEVEL"] = env_backup
        else
          ENV.delete("CLAUDE_MEMORY_LOG_LEVEL")
        end
      end
    end

    it "explicit level overrides env var" do
      env_backup = ENV["CLAUDE_MEMORY_LOG_LEVEL"]
      begin
        ENV["CLAUDE_MEMORY_LOG_LEVEL"] = "error"
        logger = described_class.new(output: output, level: :debug)
        expect(logger.level).to eq(described_class::DEBUG)
      ensure
        if env_backup
          ENV["CLAUDE_MEMORY_LOG_LEVEL"] = env_backup
        else
          ENV.delete("CLAUDE_MEMORY_LOG_LEVEL")
        end
      end
    end
  end

  describe "log methods" do
    let(:logger) { described_class.new(output: output, level: :debug) }

    it "outputs JSON with timestamp, level, and component" do
      logger.info("test", message: "hello")

      line = output.string.strip
      parsed = JSON.parse(line, symbolize_names: true)

      expect(parsed[:level]).to eq("INFO")
      expect(parsed[:component]).to eq("test")
      expect(parsed[:message]).to eq("hello")
      expect(parsed[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it "includes custom fields in output" do
      logger.debug("ingest", message: "Ingested", content_id: 42, bytes: 1024)

      parsed = JSON.parse(output.string.strip, symbolize_names: true)
      expect(parsed[:content_id]).to eq(42)
      expect(parsed[:bytes]).to eq(1024)
    end

    it "respects log level filtering" do
      warn_logger = described_class.new(output: output, level: :warn)

      warn_logger.debug("test", message: "debug")
      warn_logger.info("test", message: "info")
      warn_logger.warn("test", message: "warn")
      warn_logger.error("test", message: "error")

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(2)

      levels = lines.map { |l| JSON.parse(l, symbolize_names: true)[:level] }
      expect(levels).to eq(["WARN", "ERROR"])
    end

    it "outputs all levels when set to debug" do
      logger.debug("a", message: "d")
      logger.info("a", message: "i")
      logger.warn("a", message: "w")
      logger.error("a", message: "e")

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(4)
    end
  end

  describe "#debug?" do
    it "returns true when level is debug" do
      logger = described_class.new(output: output, level: :debug)
      expect(logger.debug?).to be true
    end

    it "returns false when level is info" do
      logger = described_class.new(output: output, level: :info)
      expect(logger.debug?).to be false
    end
  end

  describe "#info?" do
    it "returns true when level is info or lower" do
      logger = described_class.new(output: output, level: :info)
      expect(logger.info?).to be true
    end

    it "returns false when level is warn" do
      logger = described_class.new(output: output, level: :warn)
      expect(logger.info?).to be false
    end
  end
end

RSpec.describe ClaudeMemory::Logging::NullLogger do
  let(:logger) { described_class.new }

  it "silently discards all log calls" do
    expect { logger.debug("test", message: "hello") }.not_to raise_error
    expect { logger.info("test", message: "hello") }.not_to raise_error
    expect { logger.warn("test", message: "hello") }.not_to raise_error
    expect { logger.error("test", message: "hello") }.not_to raise_error
  end

  it "reports debug? and info? as false" do
    expect(logger.debug?).to be false
    expect(logger.info?).to be false
  end
end
