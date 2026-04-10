# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Embeddings::Inspector do
  let(:global_db_path) { File.join(Dir.tmpdir, "inspector_global_#{Process.pid}.sqlite3") }
  let(:project_db_path) { File.join(Dir.tmpdir, "inspector_project_#{Process.pid}.sqlite3") }

  before do
    config = instance_double(ClaudeMemory::Configuration,
      global_db_path: global_db_path,
      project_db_path: project_db_path)
    allow(ClaudeMemory::Configuration).to receive(:new).and_return(config)
  end

  after do
    FileUtils.rm_f(global_db_path)
    FileUtils.rm_f(project_db_path)
  end

  describe "#database_states" do
    it "returns empty array when no databases exist" do
      expect(described_class.new.database_states).to eq([])
    end

    it "returns metadata for databases with embedding info" do
      store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      store.set_meta("embedding_provider", "tfidf")
      store.set_meta("embedding_dimensions", "384")
      store.close

      states = described_class.new.database_states
      expect(states.size).to eq(1)
      expect(states.first).to have_attributes(
        label: "global",
        provider: "tfidf",
        dimensions: "384"
      )
    end

    it "skips databases without embedding metadata" do
      store = ClaudeMemory::Store::SQLiteStore.new(global_db_path)
      store.set_meta("some_other_key", "value")
      store.close

      expect(described_class.new.database_states).to eq([])
    end

    it "closes store even on error" do
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.set_meta("embedding_provider", "tfidf")
      store.close

      spy_store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      allow(spy_store).to receive(:get_meta).and_raise(RuntimeError, "db error")
      allow(spy_store).to receive(:close).and_call_original
      allow(ClaudeMemory::Store::SQLiteStore).to receive(:new).with(project_db_path).and_return(spy_store)

      expect { described_class.new.database_states }.to raise_error(RuntimeError, "db error")
      expect(spy_store).to have_received(:close)
    end
  end

  describe "#dimension_checks" do
    it "returns :fresh for databases without embeddings" do
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.close

      checks = described_class.new.dimension_checks("tfidf", nil)
      expect(checks.size).to eq(1)
      expect(checks.first).to have_attributes(label: "project", status: :fresh)
    end

    it "returns :match when dimensions agree" do
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.set_meta("embedding_dimensions", "384")
      store.set_meta("embedding_provider", "tfidf")
      store.close

      checks = described_class.new.dimension_checks("tfidf", nil)
      expect(checks.first).to have_attributes(
        status: :match,
        stored_dims: 384,
        stored_provider: "tfidf"
      )
    end

    it "returns :mismatch when dimensions differ" do
      store = ClaudeMemory::Store::SQLiteStore.new(project_db_path)
      store.set_meta("embedding_dimensions", "768")
      store.set_meta("embedding_provider", "fastembed")
      store.close

      checks = described_class.new.dimension_checks("tfidf", nil)
      expect(checks.first).to have_attributes(
        status: :mismatch,
        stored_dims: 768,
        current_dims: 384
      )
    end
  end
end
