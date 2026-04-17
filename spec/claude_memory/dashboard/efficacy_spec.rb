# frozen_string_literal: true

RSpec.describe ClaudeMemory::Dashboard::Efficacy::Reporter do
  def event(details: {}, status: "success", duration_ms: 10, session_id: nil, occurred_at: "2026-04-17T12:00:00Z", id: 1)
    {
      id: id,
      event_type: "recall",
      status: status,
      duration_ms: duration_ms,
      session_id: session_id,
      occurred_at: occurred_at,
      details: details
    }
  end

  describe ".report" do
    it "returns the zero-shape for an empty event list" do
      result = described_class.report([])

      expect(result[:recall_events]).to eq(0)
      expect(result[:hit_rate]).to eq(0)
      expect(result[:tool_mix]).to eq([])
      expect(result[:source_contribution]).to eq([])
      expect(result[:memory_gaps]).to eq([])
      expect(result[:recall_trace]).to eq([])
    end

    it "computes hit rate and median metrics from events" do
      events = [
        event(details: {result_count: 0, tool: "memory.recall"}),
        event(details: {result_count: 3, tool: "memory.recall"}, duration_ms: 30),
        event(details: {result_count: 5, tool: "memory.recall"}, duration_ms: 50),
        event(details: {result_count: 7, tool: "memory.recall"}, duration_ms: 70)
      ]

      result = described_class.report(events)

      expect(result[:recall_events]).to eq(4)
      expect(result[:successful_recalls]).to eq(3)
      expect(result[:empty_recalls]).to eq(1)
      expect(result[:hit_rate]).to eq(75.0)
      expect(result[:median_results_per_query]).to eq(4.0)
      expect(result[:median_latency_ms]).to eq(40.0)
    end

    it "groups tool_mix by tool and sorts by count descending" do
      events = [
        event(details: {tool: "memory.decisions", result_count: 2}),
        event(details: {tool: "memory.decisions", result_count: 0}),
        event(details: {tool: "memory.decisions", result_count: 3}),
        event(details: {tool: "memory.recall", result_count: 1}),
        event(details: {tool: "memory.recall_semantic", result_count: 4})
      ]

      result = described_class.report(events)

      expect(result[:tool_mix].map { |r| r[:tool] }).to eq([
        "memory.decisions", "memory.recall", "memory.recall_semantic"
      ])
      decisions = result[:tool_mix].first
      expect(decisions[:count]).to eq(3)
      expect(decisions[:hits]).to eq(2)
      expect(decisions[:hit_rate]).to eq(66.7)
    end

    it "surfaces zero-result queries as memory_gaps (up to the limit)" do
      events = [
        event(details: {tool: "memory.recall", query: "auth", result_count: 0}),
        event(details: {tool: "memory.recall", query: "database", result_count: 3}),
        event(details: {tool: "memory.recall", query: "rate-limit", result_count: 0})
      ]

      result = described_class.report(events)

      expect(result[:memory_gaps].size).to eq(2)
      expect(result[:memory_gaps].map { |g| g[:query] }).to contain_exactly("auth", "rate-limit")
      expect(result[:memory_gaps].first[:occurred_ago]).to be_a(String)
    end

    it "aggregates source_contribution across events' results_by_scope" do
      events = [
        event(details: {tool: "memory.recall", result_count: 3, results_by_scope: {"project" => 2, "global" => 1}}),
        event(details: {tool: "memory.decisions", result_count: 2, results_by_scope: {"global" => 2}}),
        event(details: {tool: "memory.recall", result_count: 0, results_by_scope: nil})
      ]

      result = described_class.report(events)
      by_scope = result[:source_contribution].each_with_object({}) { |r, h| h[r[:scope]] = r[:count] }

      expect(by_scope).to eq({"global" => 3, "project" => 2})
      # Sorted descending by count
      expect(result[:source_contribution].first[:scope]).to eq("global")
    end

    it "echoes the timeframe through to the response" do
      result = described_class.report([], timeframe: {since: "2026-04-10T00:00:00Z", session_id: "abc"})

      expect(result[:timeframe]).to eq({since: "2026-04-10T00:00:00Z", session_id: "abc"})
    end

    it "caps recall_trace at RECALL_TRACE_LIMIT rows in insertion order" do
      events = 60.times.map { |i| event(id: i, details: {tool: "memory.recall", query: "q#{i}", result_count: 1}) }

      result = described_class.report(events)

      expect(result[:recall_trace].size).to eq(described_class::RECALL_TRACE_LIMIT)
      expect(result[:recall_trace].first[:query]).to eq("q0")
    end
  end
end
