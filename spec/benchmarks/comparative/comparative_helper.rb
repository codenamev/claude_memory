# frozen_string_literal: true

require_relative "../benchmark_helper"
require_relative "adapters/base_adapter"
require_relative "adapters/claude_memory_adapter"
require_relative "adapters/fts_only_adapter"
require_relative "adapters/no_memory_adapter"
require_relative "adapters/claude_md_adapter"
require_relative "adapters/qmd_adapter"
require_relative "adapters/grepai_adapter"
require_relative "reporting/comparative_reporter"

module ComparativeHelpers
  COMPARATIVE_DATASET_DIR = File.expand_path("dataset", __dir__)

  # Discovers all available adapters for the current environment
  def self.available_adapters
    all = all_adapters
    available = all.select(&:available?)
    skipped = all.reject(&:available?)

    if skipped.any?
      warn "  Skipped adapters: #{skipped.map(&:name).join(", ")}"
      warn "  Run bin/setup-competitors to install"
    end

    available
  end

  # All adapter instances (available or not)
  def self.all_adapters
    [
      Adapters::ClaudeMemoryAdapter.new,
      Adapters::FtsOnlyAdapter.new,
      Adapters::NoMemoryAdapter.new,
      Adapters::ClaudeMdAdapter.new,
      Adapters::QmdAdapter.new(mode: :bm25),
      Adapters::QmdAdapter.new(mode: :vector),
      # Adapters::QmdAdapter.new(mode: :hybrid),  # Skip: ~1-2 min/query due to local GGUF inference
      Adapters::GrepaiAdapter.new
    ]
  end

  # Adapters that participate in retrieval benchmarks
  def self.retrieval_adapters
    available_adapters.reject { |a| a.is_a?(Adapters::ClaudeMdAdapter) }
  end

  # Adapters that participate in E2E benchmarks
  def self.e2e_adapters
    available_adapters.select(&:supports_e2e?)
  end

  # Select a subset of queries for comparative benchmarks.
  # 50 queries: 20 easy, 20 medium, 10 hard
  def self.comparative_query_subset(all_queries)
    easy = all_queries.select { |q| q["difficulty"] == "easy" }.first(20)
    medium = all_queries.select { |q| q["difficulty"] == "medium" }.first(20)
    hard = all_queries.select { |q| q["difficulty"] == "hard" }.first(10)
    easy + medium + hard
  end

  # Shared RSpec setup for comparative benchmark specs
  module ComparativeSetup
    def self.included(base)
      base.class_eval do
        let(:tmpdir) { Dir.mktmpdir("comparative_#{Process.pid}") }
        let(:all_facts) { BenchmarkHelpers::DatasetLoader.load_facts }
        let(:all_queries) { BenchmarkHelpers::DatasetLoader.load_queries }
        let(:comparative_queries) { ComparativeHelpers.comparative_query_subset(all_queries) }
        let(:reporter) { ComparativeHelpers::Reporting::ComparativeReporter.new }

        after do
          FileUtils.rm_rf(tmpdir)
        end

        # Create a subdirectory for a specific adapter
        def adapter_dir(adapter)
          dir = File.join(tmpdir, adapter.name.downcase.gsub(/[^a-z0-9]+/, "_"))
          FileUtils.mkdir_p(File.join(dir, ".claude"))
          dir
        end
      end
    end
  end
end
