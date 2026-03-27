# frozen_string_literal: true

require "yaml"
require "tmpdir"
require "fileutils"
require "digest"
# Load ClaudeMemory and eval helpers
require_relative "../evals/support/eval_helpers"

module BenchmarkHelpers
  DATASET_DIR = File.expand_path("dataset", __dir__)

  # Standard IR metrics used for retrieval benchmarks
  module IRMetrics
    # Recall@k: fraction of relevant items retrieved in top-k
    def recall_at_k(retrieved_ids, relevant_ids, k)
      return 1.0 if relevant_ids.empty? # abstention: no relevant items expected

      retrieved_top_k = retrieved_ids.first(k).to_set
      hits = retrieved_top_k.intersection(relevant_ids.to_set).size
      hits.to_f / relevant_ids.size
    end

    # Mean Reciprocal Rank: 1/position of first relevant result
    def mrr(retrieved_ids, relevant_ids)
      return 1.0 if relevant_ids.empty? # abstention

      relevant_set = relevant_ids.to_set
      retrieved_ids.each_with_index do |id, idx|
        return 1.0 / (idx + 1) if relevant_set.include?(id)
      end
      0.0
    end

    # Normalized Discounted Cumulative Gain at k (binary relevance)
    def ndcg_at_k(retrieved_ids, relevant_ids, k)
      return 1.0 if relevant_ids.empty?

      relevant_set = relevant_ids.to_set
      top_k = retrieved_ids.first(k)

      # DCG: sum of 1/log2(rank+1) for each relevant result
      dcg = top_k.each_with_index.sum do |id, idx|
        relevant_set.include?(id) ? 1.0 / Math.log2(idx + 2) : 0.0
      end

      # Ideal DCG: best possible ordering
      ideal_k = [relevant_ids.size, k].min
      idcg = (0...ideal_k).sum { |idx| 1.0 / Math.log2(idx + 2) }

      return 0.0 if idcg.zero?
      dcg / idcg
    end

    # Precision@k: fraction of top-k results that are relevant
    def precision_at_k(retrieved_ids, relevant_ids, k)
      top_k = retrieved_ids.first(k)
      return 1.0 if top_k.empty? && relevant_ids.empty?
      return 0.0 if top_k.empty?

      relevant_set = relevant_ids.to_set
      hits = top_k.count { |id| relevant_set.include?(id) }
      hits.to_f / top_k.size
    end

    # Abstention accuracy: for queries with no relevant facts,
    # measure how few results are returned
    def abstention_precision(retrieved_ids, k)
      top_k = retrieved_ids.first(k)
      top_k.empty? ? 1.0 : 0.0
    end
  end

  # Loads YAML dataset files
  class DatasetLoader
    def self.load_facts(path = File.join(DATASET_DIR, "facts.yml"))
      YAML.load_file(path)
    end

    def self.load_queries(path = File.join(DATASET_DIR, "retrieval_queries.yml"))
      YAML.load_file(path)
    end

    def self.load_resolution_cases(path = File.join(DATASET_DIR, "resolution_cases.yml"))
      YAML.load_file(path)
    end

    def self.load_e2e_scenarios(path = File.join(DATASET_DIR, "e2e_scenarios.yml"))
      YAML.load_file(path)
    end

    def self.load_extraction_cases(path = File.join(DATASET_DIR, "extraction_cases.yml"))
      YAML.load_file(path)
    end

    def self.load_llm_extraction_cases(path = File.join(DATASET_DIR, "extraction_cases_llm.yml"))
      YAML.load_file(path)
    end
  end

  # Extraction quality metrics for distillation benchmarks
  module ExtractionMetrics
    # Precision: fraction of extracted items that match an expected item
    def extraction_precision(extracted, expected, &match_fn)
      return 1.0 if extracted.empty? && expected.empty?
      return 0.0 if extracted.empty?

      hits = extracted.count { |e| expected.any? { |exp| match_fn.call(e, exp) } }
      hits.to_f / extracted.size
    end

    # Recall: fraction of expected items found in extracted items
    def extraction_recall(extracted, expected, &match_fn)
      return 1.0 if expected.empty?

      hits = expected.count { |exp| extracted.any? { |e| match_fn.call(e, exp) } }
      hits.to_f / expected.size
    end

    # F1: harmonic mean of precision and recall
    def f1_score(precision, recall)
      return 0.0 if precision + recall == 0
      2.0 * precision * recall / (precision + recall)
    end

    # Generic hash-subset matcher: checks that all expected keys match.
    # Keys ending in _pattern use regex matching.
    # Keys ending in _contains use substring matching (for non-deterministic LLM output).
    # All others use exact match.
    def matches?(extracted, expected)
      expected.all? do |key, value|
        str_key = key.to_s
        if str_key.end_with?("_contains")
          real_key = str_key.sub(/_contains$/, "")
          extracted[real_key.to_sym].to_s.downcase.include?(value.to_s.downcase)
        elsif str_key.end_with?("_pattern")
          real_key = str_key.sub(/_pattern$/, "")
          extracted[real_key.to_sym].to_s.downcase.match?(Regexp.new(value.to_s.downcase))
        else
          extracted[key.to_sym].to_s.downcase == value.to_s.downcase
        end
      end
    end
  end

  # Extends MemoryFixtureBuilder to load facts from dataset YAML
  class BenchmarkFixtureBuilder
    attr_reader :store, :fts, :fact_id_map, :embedding_generator

    # @param db_path [String] path to SQLite database
    # @param embedding_generator [#generate_passage, #generate, nil] optional embedding generator
    #   If provided, generates and stores embeddings for each loaded fact.
    #   Prefers generate_passage (asymmetric passage encoding) when available.
    def initialize(db_path, embedding_generator: nil)
      @builder = EvalHelpers::MemoryFixtureBuilder.new(db_path)
      @store = @builder.store
      @fts = @builder.fts
      @fact_id_map = {} # maps dataset fact ID (string) -> database fact ID (integer)
      @embedding_generator = embedding_generator
    end

    # Load a single fact from dataset format into the database
    # Returns the database-assigned fact ID
    def load_fact(fact_data)
      status = fact_data["status"] || "active"
      scope = fact_data["scope"] || "project"

      # Create content item
      text = fact_data["text"]
      content_id = @store.upsert_content_item(
        source: "benchmark",
        session_id: "benchmark-session",
        text_hash: Digest::SHA256.hexdigest(text),
        byte_len: text.bytesize,
        raw_text: text
      )

      # Create entity for subject
      entity_id = @store.find_or_create_entity(
        type: "repo",
        name: fact_data["subject"] || "test-project"
      )

      # Create fact
      fact_id = @store.insert_fact(
        subject_entity_id: entity_id,
        predicate: fact_data["predicate"],
        object_literal: fact_data["object"],
        scope: scope,
        confidence: fact_data.fetch("confidence", 1.0),
        valid_from: fact_data["valid_from"],
        status: status
      )

      # Mark as superseded if needed
      if status == "superseded" && fact_data["valid_to"]
        @store.update_fact(fact_id, status: "superseded", valid_to: fact_data["valid_to"])
      end

      # Link fact to content (provenance)
      strength = fact_data["strength"] || "stated"
      @store.insert_provenance(
        fact_id: fact_id,
        content_item_id: content_id,
        quote: fact_data["object"],
        strength: strength
      )

      # Index for FTS
      fts_text = fact_data["fts_keywords"] ? "#{text} #{fact_data["fts_keywords"]}" : text
      @fts.index_content_item(content_id, fts_text)

      # Track mapping
      dataset_id = fact_data["id"]
      @fact_id_map[dataset_id] = fact_id if dataset_id

      # Generate and store embedding if generator is available
      if @embedding_generator && status == "active"
        embed_text = "#{fact_data["predicate"]}: #{fact_data["object"]}. #{text}"
        embedding = if @embedding_generator.respond_to?(:generate_passage)
          @embedding_generator.generate_passage(embed_text)
        else
          @embedding_generator.generate(embed_text)
        end
        @store.update_fact_embedding(fact_id, embedding)
      end

      # Handle supersession links
      if fact_data["supersedes"] && @fact_id_map[fact_data["supersedes"]]
        old_fact_id = @fact_id_map[fact_data["supersedes"]]
        @store.insert_fact_link(
          from_fact_id: fact_id,
          to_fact_id: old_fact_id,
          link_type: "supersedes"
        )
      end

      fact_id
    end

    # Load all facts from the dataset, respecting order for supersession links
    def load_all_facts(facts)
      facts.each { |f| load_fact(f) }
    end

    # Load only active (non-superseded) facts
    def load_active_facts(facts)
      facts.reject { |f| f["status"] == "superseded" }.each { |f| load_fact(f) }
    end

    def close
      @builder.close
    end

    # Translate dataset fact IDs to database fact IDs
    def resolve_ids(dataset_ids)
      dataset_ids.filter_map { |did| @fact_id_map[did] }
    end
  end

  # Collects and reports benchmark metrics
  class MetricsCollector
    attr_reader :results

    def initialize
      @results = Hash.new { |h, k| h[k] = [] }
    end

    def record(category, metric_name, value)
      @results["#{category}:#{metric_name}"] << value
    end

    def average(category, metric_name)
      values = @results["#{category}:#{metric_name}"]
      return 0.0 if values.empty?
      values.sum / values.size.to_f
    end

    def count(category, metric_name)
      @results["#{category}:#{metric_name}"].size
    end

    def summary
      summary = {}
      @results.each do |key, values|
        next if values.empty?
        summary[key] = {
          mean: (values.sum / values.size.to_f).round(4),
          count: values.size,
          min: values.min.round(4),
          max: values.max.round(4)
        }
      end
      summary
    end

    def format_report(title)
      lines = ["", "=" * 60, title, "=" * 60, ""]

      # Group by category
      categories = @results.keys.map { |k| k.split(":").first }.uniq
      categories.each do |cat|
        cat_metrics = @results.select { |k, _| k.start_with?("#{cat}:") }
        next if cat_metrics.empty?

        lines << "  #{cat}:"
        cat_metrics.each do |key, values|
          metric = key.split(":").last
          avg = (values.sum / values.size.to_f).round(4)
          lines << "    #{metric}=#{avg}  (#{values.size} queries)"
        end
        lines << ""
      end

      lines.join("\n")
    end
  end

  # Helpers for Claude distillation benchmarks (Tier 1-3)
  module DistillationSetup
    # Set up a tmpdir with .mcp.json pointing to claude-memory serve-mcp
    def setup_tmpdir_with_mcp
      tmpdir = Dir.mktmpdir("distill-bench")
      claude_dir = File.join(tmpdir, ".claude")
      FileUtils.mkdir_p(claude_dir)

      mcp_config = {
        "mcpServers" => {
          "memory" => {
            "type" => "stdio",
            "command" => "claude-memory",
            "args" => ["serve-mcp", "--db", File.join(claude_dir, "memory.sqlite3")]
          }
        }
      }
      File.write(File.join(tmpdir, ".mcp.json"), JSON.generate(mcp_config))
      tmpdir
    end

    # Build the extraction prompt for Claude
    def extraction_prompt(text)
      <<~PROMPT
        Extract all knowledge from the following transcript text. Use the memory.store_extraction tool to save any entities, facts, and decisions you find.

        Be thorough: extract conventions, architectural decisions, testing strategies, preferences, and any other notable knowledge.

        Transcript:
        #{text}
      PROMPT
    end

    # Build the distillation prompt for e2e scenarios
    def distillation_prompt(scenario)
      text = scenario["facts_to_load"].map { |f| f["text"] }.join("\n\n")
      <<~PROMPT
        Read and memorize the following project knowledge. Use the memory.store_extraction tool to save all entities, facts, and decisions.

        #{text}
      PROMPT
    end

    # Read stored facts from a tmpdir's database
    def read_stored_facts(tmpdir)
      db_path = File.join(tmpdir, ".claude", "memory.sqlite3")
      return {facts: [], entities: []} unless File.exist?(db_path)

      store = ClaudeMemory::Store::SQLiteStore.new(db_path)
      facts = store.facts.where(status: "active").all
      entities = store.entities.all
      store.close
      {facts: facts, entities: entities}
    end
  end

  # Shared RSpec setup for benchmark specs
  module BenchmarkSetup
    def self.included(base)
      base.class_eval do
        let(:tmpdir) { Dir.mktmpdir("benchmark_#{Process.pid}") }
        let(:db_path) { File.join(tmpdir, ".claude/memory.sqlite3") }
        let(:all_facts) { BenchmarkHelpers::DatasetLoader.load_facts }
        let(:all_queries) { BenchmarkHelpers::DatasetLoader.load_queries }
        let(:metrics) { BenchmarkHelpers::MetricsCollector.new }

        before do
          FileUtils.mkdir_p(File.dirname(db_path))
        end

        after do
          FileUtils.rm_rf(tmpdir)
        end
      end
    end
  end
end
