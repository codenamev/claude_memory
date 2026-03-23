# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClaudeMemory::Core::RRFusion do
  describe ".fuse" do
    it "combines results from both sources" do
      vector = [
        {fact: {id: 1}, similarity: 0.9},
        {fact: {id: 2}, similarity: 0.8}
      ]
      text = [
        {fact: {id: 3}, similarity: 0.5}
      ]

      fused = described_class.fuse(vector, text, 10)

      expect(fused.map { |r| r[:fact][:id] }).to include(1, 2, 3)
    end

    it "boosts results appearing in both rankings" do
      vector = [
        {fact: {id: 1}, similarity: 0.9},
        {fact: {id: 2}, similarity: 0.8}
      ]
      text = [
        {fact: {id: 1}, similarity: 0.5}, # Also in vector
        {fact: {id: 3}, similarity: 0.5}
      ]

      fused = described_class.fuse(vector, text, 10)

      # Fact 1 appears in both rankings, should rank highest
      expect(fused.first[:fact][:id]).to eq(1)

      # Fact 1's RRF score should be higher than fact 2 (which only appears in vector)
      fact_1_score = fused.find { |r| r[:fact][:id] == 1 }[:similarity]
      fact_2_score = fused.find { |r| r[:fact][:id] == 2 }[:similarity]
      expect(fact_1_score).to be > fact_2_score
    end

    it "applies top-rank bonus" do
      # Two results at rank 1 in different lists
      vector = [{fact: {id: 1}, similarity: 0.9}]
      text = [{fact: {id: 2}, similarity: 0.5}]

      fused = described_class.fuse(vector, text, 10)

      # Both get top-rank bonus (0.05) plus RRF score
      scores = fused.map { |r| r[:similarity] }
      expect(scores).to all(be > 0)
    end

    it "respects weight parameters" do
      vector = [{fact: {id: 1}, similarity: 0.9}]
      text = [{fact: {id: 2}, similarity: 0.5}]

      # Higher vector weight
      fused = described_class.fuse(vector, text, 10, vector_weight: 2.0, text_weight: 1.0)

      fact_1_score = fused.find { |r| r[:fact][:id] == 1 }[:similarity]
      fact_2_score = fused.find { |r| r[:fact][:id] == 2 }[:similarity]

      # Vector-only result should score higher with 2x weight
      expect(fact_1_score).to be > fact_2_score
    end

    it "preserves vector result data when fact appears in both" do
      vector = [{fact: {id: 1, name: "vector_data"}, similarity: 0.9, source: :project}]
      text = [{fact: {id: 1, name: "text_data"}, similarity: 0.5, source: :project}]

      fused = described_class.fuse(vector, text, 10)

      # Should keep vector data (processed first)
      expect(fused.first[:fact][:name]).to eq("vector_data")
    end

    it "limits results to specified count" do
      vector = 5.times.map { |i| {fact: {id: i}, similarity: 1.0 - (i * 0.1)} }
      text = 5.times.map { |i| {fact: {id: i + 10}, similarity: 0.5} }

      fused = described_class.fuse(vector, text, 3)

      expect(fused.length).to eq(3)
    end

    it "handles empty vector results" do
      fused = described_class.fuse([], [{fact: {id: 1}, similarity: 0.5}], 10)
      expect(fused.length).to eq(1)
    end

    it "handles empty text results" do
      fused = described_class.fuse([{fact: {id: 1}, similarity: 0.9}], [], 10)
      expect(fused.length).to eq(1)
    end

    it "handles both empty" do
      fused = described_class.fuse([], [], 10)
      expect(fused).to eq([])
    end

    describe "explain mode" do
      it "includes score traces when explain: true" do
        vector = [{fact: {id: 1}, similarity: 0.9}]
        text = [{fact: {id: 2}, similarity: 0.5}]

        fused = described_class.fuse(vector, text, 10, explain: true)

        trace_1 = fused.find { |r| r[:fact][:id] == 1 }[:score_trace]
        expect(trace_1[:vec_rank]).to eq(1)
        expect(trace_1[:vec_score]).to eq(0.9)
        expect(trace_1[:fts_rank]).to be_nil
        expect(trace_1[:rrf_final]).to be_a(Float)

        trace_2 = fused.find { |r| r[:fact][:id] == 2 }[:score_trace]
        expect(trace_2[:fts_rank]).to eq(1)
        expect(trace_2[:fts_score]).to eq(0.5)
        expect(trace_2[:vec_rank]).to be_nil
      end

      it "shows both sources for dual-ranked facts" do
        vector = [{fact: {id: 1}, similarity: 0.9}]
        text = [{fact: {id: 1}, similarity: 0.7}]

        fused = described_class.fuse(vector, text, 10, explain: true)

        trace = fused.first[:score_trace]
        expect(trace[:vec_rank]).to eq(1)
        expect(trace[:fts_rank]).to eq(1)
        expect(trace[:vec_rrf]).to be_a(Float)
        expect(trace[:fts_rrf]).to be_a(Float)
        expect(trace[:rrf_final]).to be_within(0.001).of(trace[:vec_rrf] + trace[:fts_rrf])
      end

      it "omits score traces when explain: false" do
        vector = [{fact: {id: 1}, similarity: 0.9}]
        fused = described_class.fuse(vector, [], 10, explain: false)
        expect(fused.first).not_to have_key(:score_trace)
      end
    end

    it "sorts by RRF score descending" do
      vector = [
        {fact: {id: 1}, similarity: 0.9},
        {fact: {id: 2}, similarity: 0.5}
      ]
      text = [
        {fact: {id: 3}, similarity: 0.5},
        {fact: {id: 1}, similarity: 0.5}
      ]

      fused = described_class.fuse(vector, text, 10)

      scores = fused.map { |r| r[:similarity] }
      expect(scores).to eq(scores.sort.reverse)
    end
  end
end
