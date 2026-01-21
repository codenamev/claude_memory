# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Configuration do
  describe "#initialize" do
    it "accepts an ENV hash" do
      env = {"HOME" => "/home/user"}
      config = described_class.new(env)
      expect(config.env).to eq(env)
    end

    it "defaults to ENV" do
      config = described_class.new
      expect(config.env).to eq(ENV)
    end
  end

  describe "#home_dir" do
    it "returns HOME from env" do
      config = described_class.new({"HOME" => "/custom/home"})
      expect(config.home_dir).to eq("/custom/home")
    end

    it "falls back to File.expand_path when HOME missing" do
      config = described_class.new({})
      expect(config.home_dir).to eq(File.expand_path("~"))
    end
  end

  describe "#project_dir" do
    it "returns CLAUDE_PROJECT_DIR when set" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/path/to/project"})
      expect(config.project_dir).to eq("/path/to/project")
    end

    it "falls back to Dir.pwd when not set" do
      config = described_class.new({})
      expect(config.project_dir).to eq(Dir.pwd)
    end
  end

  describe "#global_db_path" do
    it "returns path to global database" do
      config = described_class.new({"HOME" => "/home/user"})
      expect(config.global_db_path).to eq("/home/user/.claude/memory.sqlite3")
    end
  end

  describe "#project_db_path" do
    it "returns path to project database using project_dir" do
      config = described_class.new({"CLAUDE_PROJECT_DIR" => "/my/project"})
      expect(config.project_db_path).to eq("/my/project/.claude/memory.sqlite3")
    end

    it "uses Dir.pwd when CLAUDE_PROJECT_DIR not set" do
      config = described_class.new({})
      expected_path = File.join(Dir.pwd, ".claude/memory.sqlite3")
      expect(config.project_db_path).to eq(expected_path)
    end

    it "accepts explicit project_path override" do
      config = described_class.new({})
      path = config.project_db_path("/custom/path")
      expect(path).to eq("/custom/path/.claude/memory.sqlite3")
    end
  end

  describe "#session_id" do
    it "returns CLAUDE_SESSION_ID when set" do
      config = described_class.new({"CLAUDE_SESSION_ID" => "session-123"})
      expect(config.session_id).to eq("session-123")
    end

    it "returns nil when not set" do
      config = described_class.new({})
      expect(config.session_id).to be_nil
    end
  end

  describe "#transcript_path" do
    it "returns CLAUDE_TRANSCRIPT_PATH when set" do
      config = described_class.new({"CLAUDE_TRANSCRIPT_PATH" => "/tmp/transcript.jsonl"})
      expect(config.transcript_path).to eq("/tmp/transcript.jsonl")
    end

    it "returns nil when not set" do
      config = described_class.new({})
      expect(config.transcript_path).to be_nil
    end
  end
end
