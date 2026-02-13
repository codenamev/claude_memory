# frozen_string_literal: true

module ComparativeHelpers
  module Reporting
    # Collects metrics from multiple adapters and produces side-by-side reports.
    class ComparativeReporter
      def initialize
        @retrieval = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
        @efficiency = {}
        @e2e = {}
      end

      # Record retrieval metrics for an adapter at a given difficulty.
      # @param adapter_name [String]
      # @param difficulty [String] e.g. "easy", "medium", "hard"
      # @param metrics [Hash] e.g. { recall_5: 0.95, recall_10: 0.98, mrr: 0.85, ndcg_10: 0.9, query_count: 20 }
      def add_retrieval_results(adapter_name, difficulty, metrics)
        @retrieval[difficulty][adapter_name] = metrics
      end

      # Record efficiency metrics for an adapter.
      # @param adapter_name [String]
      # @param metrics [Hash] e.g. { setup_time_ms: 120, query_latency_ms: 45, index_size_kb: 340 }
      def add_efficiency_results(adapter_name, metrics)
        @efficiency[adapter_name] = metrics
      end

      # Record E2E metrics for an adapter.
      # @param adapter_name [String]
      # @param metrics [Hash] e.g. { acceptance_rate: 0.9, avg_score: 0.85, scenarios: 10 }
      def add_e2e_results(adapter_name, metrics)
        @e2e[adapter_name] = metrics
      end

      # Generate formatted terminal report
      def terminal_report
        lines = []
        lines << ""
        lines << "=" * 70
        lines << "COMPARATIVE BENCHMARK RESULTS (#{Time.now.strftime("%Y-%m-%d")})"
        lines << "=" * 70

        lines.concat(retrieval_section) if @retrieval.any?
        lines.concat(efficiency_section) if @efficiency.any?
        lines.concat(e2e_section) if @e2e.any?

        lines << ""
        lines.join("\n")
      end

      # Generate markdown report for saving to file
      def markdown_report
        lines = []
        lines << "# Comparative Benchmark Results"
        lines << ""
        lines << "_Generated: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}_"
        lines << ""

        lines.concat(retrieval_markdown) if @retrieval.any?
        lines.concat(efficiency_markdown) if @efficiency.any?
        lines.concat(e2e_markdown) if @e2e.any?

        lines.join("\n")
      end

      private

      # ---- Terminal sections ----

      def retrieval_section
        adapters = retrieval_adapter_names
        col_width = adapters.map(&:length).max
        col_width = [col_width, 15].max

        total_queries = @retrieval.values.sum { |by_adapter|
          by_adapter.values.first&.[](:query_count) || 0
        }

        lines = []
        lines << ""
        lines << "RETRIEVAL QUALITY (#{total_queries} queries)"
        lines << format_header(adapters, col_width)

        %w[easy medium hard].each do |difficulty|
          next unless @retrieval.key?(difficulty)

          query_count = @retrieval[difficulty].values.first&.[](:query_count) || 0
          lines << "#{difficulty.capitalize} (#{query_count}q):"

          %i[recall_5 recall_10 mrr ndcg_10].each do |metric|
            values = adapters.map { |a|
              @retrieval[difficulty].dig(a, metric)
            }
            next if values.compact.empty?

            label = metric_label(metric)
            lines << format_row(label, adapters, col_width) { |adapter|
              val = @retrieval[difficulty].dig(adapter, metric)
              val ? format("%.3f", val) : "-"
            }
          end
          lines << ""
        end

        lines
      end

      def efficiency_section
        adapters = @efficiency.keys
        col_width = adapters.map(&:length).max
        col_width = [col_width, 15].max

        lines = []
        lines << "RESOURCE EFFICIENCY"
        lines << format_header(adapters, col_width)

        %i[setup_time_ms query_latency_ms index_size_kb].each do |metric|
          label = metric_label(metric)
          lines << format_row(label, adapters, col_width) { |adapter|
            val = @efficiency.dig(adapter, metric)
            val ? val.round(1).to_s : "-"
          }
        end
        lines << ""
        lines
      end

      def e2e_section
        adapters = @e2e.keys
        col_width = adapters.map(&:length).max
        col_width = [col_width, 15].max

        scenario_count = @e2e.values.first&.[](:scenarios) || 0

        lines = []
        lines << "E2E CLAUDE IMPACT (#{scenario_count} scenarios, real Claude)"
        lines << format_header(adapters, col_width)

        %i[acceptance_rate avg_score].each do |metric|
          label = metric_label(metric)
          lines << format_row(label, adapters, col_width) { |adapter|
            val = @e2e.dig(adapter, metric)
            val ? format("%.2f", val) : "-"
          }
        end
        lines << ""
        lines
      end

      # ---- Markdown sections ----

      def retrieval_markdown
        adapters = retrieval_adapter_names
        lines = []
        lines << "## Retrieval Quality"
        lines << ""

        %w[easy medium hard].each do |difficulty|
          next unless @retrieval.key?(difficulty)

          query_count = @retrieval[difficulty].values.first&.[](:query_count) || 0
          lines << "### #{difficulty.capitalize} (#{query_count} queries)"
          lines << ""

          # Table header
          lines << "| Metric | #{adapters.join(" | ")} |"
          lines << "| --- | #{adapters.map { "---" }.join(" | ")} |"

          %i[recall_5 recall_10 mrr ndcg_10].each do |metric|
            values = adapters.map { |a|
              val = @retrieval[difficulty].dig(a, metric)
              val ? format("%.3f", val) : "-"
            }
            next if values.all? { |v| v == "-" }

            lines << "| #{metric_label(metric)} | #{values.join(" | ")} |"
          end
          lines << ""
        end

        lines
      end

      def efficiency_markdown
        adapters = @efficiency.keys
        lines = []
        lines << "## Resource Efficiency"
        lines << ""
        lines << "| Metric | #{adapters.join(" | ")} |"
        lines << "| --- | #{adapters.map { "---" }.join(" | ")} |"

        %i[setup_time_ms query_latency_ms index_size_kb].each do |metric|
          values = adapters.map { |a|
            val = @efficiency.dig(a, metric)
            val ? val.round(1).to_s : "-"
          }
          lines << "| #{metric_label(metric)} | #{values.join(" | ")} |"
        end
        lines << ""
        lines
      end

      def e2e_markdown
        adapters = @e2e.keys
        lines = []
        lines << "## E2E Claude Impact"
        lines << ""
        lines << "| Metric | #{adapters.join(" | ")} |"
        lines << "| --- | #{adapters.map { "---" }.join(" | ")} |"

        %i[acceptance_rate avg_score].each do |metric|
          values = adapters.map { |a|
            val = @e2e.dig(a, metric)
            val ? format("%.2f", val) : "-"
          }
          lines << "| #{metric_label(metric)} | #{values.join(" | ")} |"
        end
        lines << ""
        lines
      end

      # ---- Formatting helpers ----

      def retrieval_adapter_names
        @retrieval.values.flat_map(&:keys).uniq
      end

      def format_header(adapters, col_width)
        padding = " " * 18
        cols = adapters.map { |a| a.ljust(col_width) }.join("  ")
        "#{padding}#{cols}"
      end

      def format_row(label, adapters, col_width)
        padding = "  #{label.ljust(16)}"
        cols = adapters.map { |a| yield(a).ljust(col_width) }.join("  ")
        "#{padding}#{cols}"
      end

      METRIC_LABELS = {
        recall_5: "Recall@5",
        recall_10: "Recall@10",
        mrr: "MRR",
        ndcg_10: "nDCG@10",
        setup_time_ms: "Setup (ms)",
        query_latency_ms: "Query (ms)",
        index_size_kb: "Index (KB)",
        acceptance_rate: "Accept rate",
        avg_score: "Avg score"
      }.freeze

      def metric_label(metric)
        METRIC_LABELS.fetch(metric, metric.to_s)
      end
    end
  end
end
