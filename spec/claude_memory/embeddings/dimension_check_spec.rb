# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe ClaudeMemory::Embeddings::DimensionCheck do
  let(:db_path) { File.join(Dir.tmpdir, "dimcheck_test_#{Process.pid}.sqlite3") }
  let(:store) { ClaudeMemory::Store::SQLiteStore.new(db_path) }

  after do
    store.close
    FileUtils.rm_f(db_path)
  end

  describe ".call" do
    context "when no prior embeddings exist (fresh)" do
      it "returns :fresh status" do
        provider = double("provider", dimensions: 384)
        result = described_class.call(store, provider)

        expect(result.status).to eq(:fresh)
        expect(result.stored).to be_nil
        expect(result.current).to eq(384)
      end
    end

    context "when stored dimensions match provider" do
      before { store.set_meta("embedding_dimensions", "384") }

      it "returns :match status" do
        provider = double("provider", dimensions: 384)
        result = described_class.call(store, provider)

        expect(result.status).to eq(:match)
        expect(result.stored).to eq(384)
        expect(result.current).to eq(384)
      end
    end

    context "when stored dimensions differ from provider" do
      before { store.set_meta("embedding_dimensions", "384") }

      it "returns :mismatch status" do
        provider = double("provider", dimensions: 1536)
        result = described_class.call(store, provider)

        expect(result.status).to eq(:mismatch)
        expect(result.stored).to eq(384)
        expect(result.current).to eq(1536)
      end
    end
  end

  describe "Result" do
    it "is a Data value object" do
      result = described_class::Result.new(status: :match, stored: 384, current: 384)

      expect(result.status).to eq(:match)
      expect(result.stored).to eq(384)
      expect(result.current).to eq(384)
      expect(result).to be_frozen
    end
  end
end
