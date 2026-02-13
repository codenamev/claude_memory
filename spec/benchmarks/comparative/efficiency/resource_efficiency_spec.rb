# frozen_string_literal: true

require_relative "../comparative_helper"

RSpec.describe "Resource Efficiency", :comparative, :benchmark do
  include ComparativeHelpers::ComparativeSetup

  let(:adapters) { ComparativeHelpers.retrieval_adapters }
  let(:sample_queries) { comparative_queries.first(20) }

  describe "setup and query performance" do
    it "measures setup time, query latency, and index size per adapter" do
      adapter_metrics = {}

      adapters.each do |adapter|
        dir = adapter_dir(adapter)

        # Measure setup time
        setup_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        adapter.setup(all_facts, dir)
        setup_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - setup_start
        setup_time_ms = (setup_elapsed * 1000).round(2)

        # Measure index size on disk
        index_size_bytes = dir_disk_usage(dir)
        index_size_kb = (index_size_bytes / 1024.0).round(1)

        # Measure query latency (average across sample queries)
        latencies = []
        sample_queries.each do |query_data|
          query_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          adapter.search(query_data["query"], limit: 10)
          query_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - query_start
          latencies << (query_elapsed * 1000)
        end

        avg_latency = latencies.empty? ? 0.0 : latencies.sum / latencies.size

        adapter_metrics[adapter.name] = {
          setup_time_ms: setup_time_ms,
          query_latency_ms: avg_latency.round(2),
          index_size_kb: index_size_kb
        }

        reporter.add_efficiency_results(adapter.name, adapter_metrics[adapter.name])

        puts "  #{adapter.name}:"
        puts "    Setup:    #{setup_time_ms} ms"
        puts "    Query:    #{avg_latency.round(2)} ms (avg over #{latencies.size} queries)"
        puts "    Index:    #{index_size_kb} KB"
      end

      # Print comparative table
      puts reporter.terminal_report

      # Soft assertion: we got metrics for at least the always-available adapters
      expect(adapter_metrics.size).to be >= 2,
        "Should have metrics for at least ClaudeMemory + FTS-only"

      # Cleanup
      adapters.each(&:teardown)
    end
  end

  describe "memory footprint" do
    it "measures RSS delta per adapter" do
      skip "RSS measurement not reliable in CI" if ENV["CI"]

      adapters.each do |adapter|
        dir = adapter_dir(adapter)

        rss_before = current_rss_kb
        adapter.setup(all_facts, dir)
        rss_after = current_rss_kb

        delta = rss_after - rss_before
        puts "  #{adapter.name} RSS delta: #{delta} KB"

        adapter.teardown
      end
    end
  end

  private

  def dir_disk_usage(dir)
    Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
      .select { |f| File.file?(f) }
      .sum { |f| File.size(f) }
  rescue
    0
  end

  def current_rss_kb
    `ps -o rss= -p #{Process.pid}`.strip.to_i
  rescue
    0
  end
end
