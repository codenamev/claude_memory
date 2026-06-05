# frozen_string_literal: true

RSpec.describe ClaudeMemory::Commands::Checks::EmbeddingsCheck do
  describe "#call" do
    let(:check) { described_class.new }
    let(:result) { check.call }

    it "returns the active provider name and dimensions" do
      expect(result[:details][:provider]).to be_a(String)
      expect(result[:details][:dimensions]).to be_a(Integer)
      expect(result[:message]).to match(/Embedding provider:/)
    end

    it "is labeled 'embeddings'" do
      expect(result[:label]).to eq("embeddings")
    end

    context "when on default tfidf and fastembed is loadable" do
      before do
        # Override ENV so resolver returns tfidf
        allow(check).to receive(:fastembed_loadable?).and_return(true)
        stub_const("ENV", ENV.to_h.merge("CLAUDE_MEMORY_EMBEDDING_PROVIDER" => nil, "CLAUDE_MEMORY_EMBEDDING_MODEL" => nil))
      end

      it "warns and recommends setup-vectors" do
        expect(result[:status]).to eq(:warning)
        expect(result[:warnings].join).to include("CLAUDE_MEMORY_EMBEDDING_PROVIDER=fastembed")
        expect(result[:warnings].join).to include("setup-vectors")
      end
    end

    context "when on default tfidf and fastembed is NOT loadable" do
      before do
        allow(check).to receive(:fastembed_loadable?).and_return(false)
        stub_const("ENV", ENV.to_h.merge("CLAUDE_MEMORY_EMBEDDING_PROVIDER" => nil, "CLAUDE_MEMORY_EMBEDDING_MODEL" => nil))
      end

      it "warns about install rather than just env override" do
        expect(result[:status]).to eq(:warning)
        expect(result[:warnings].join).to include("not installed")
        expect(result[:warnings].join).to include("setup-vectors")
      end
    end
  end
end
