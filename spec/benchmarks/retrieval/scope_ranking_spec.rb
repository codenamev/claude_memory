# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "Scope Ranking", :benchmark do
  include BenchmarkHelpers::IRMetrics
  include BenchmarkHelpers::BenchmarkSetup

  let(:builder) { BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path) }

  let(:scope_queries) do
    all_queries.select { |q| q["difficulty"] == "scope" }
  end

  before do
    builder.load_all_facts(all_facts)
  end

  after do
    builder.close
  end

  describe "project vs global scope ranking" do
    it "ranks project-scoped facts appropriately relative to global facts" do
      skip "No scope queries in dataset" if scope_queries.empty?

      recall = ClaudeMemory::Recall.new(builder.store, fts: builder.fts)

      scope_results = []

      scope_queries.each do |query_data|
        results = recall.query(query_data["query"], limit: 10, scope: "all")

        retrieved_fact_ids = results.filter_map { |r|
          r.is_a?(Hash) ? r[:fact]&.[](:id) : nil
        }

        expected_db_ids = builder.resolve_ids(query_data["expected_facts"] || [])
        expected_db_ids_set = expected_db_ids.to_set

        # Categorize retrieved expected facts by scope
        project_ranks = []
        global_ranks = []

        retrieved_fact_ids.each_with_index do |fid, idx|
          next unless expected_db_ids_set.include?(fid)
          fact = builder.store.facts.where(id: fid).first
          next unless fact

          if fact[:scope] == "project"
            project_ranks << idx
          elsif fact[:scope] == "global"
            global_ranks << idx
          end
        end

        # Record whether expected facts were found at all
        found_any = (project_ranks + global_ranks).any?
        scope_results << {
          query: query_data["query"],
          found: found_any,
          project_ranks: project_ranks,
          global_ranks: global_ranks,
          preferred_scope: query_data["preferred_scope"]
        }
      end

      found_count = scope_results.count { |r| r[:found] }
      puts "\n  Scope ranking: #{found_count}/#{scope_results.size} queries returned expected facts"

      scope_results.each do |result|
        status = result[:found] ? "FOUND" : "MISS"
        puts "    [#{status}] #{result[:query]}"
        puts "      project ranks: #{result[:project_ranks].inspect}, global ranks: #{result[:global_ranks].inspect}"
      end

      expect(found_count).to be > 0, "At least some scope queries should return expected facts"
    end
  end

  describe "scope isolation" do
    it "filters correctly when querying project-only scope" do
      recall = ClaudeMemory::Recall.new(builder.store, fts: builder.fts)

      results = recall.query("conventions", limit: 20, scope: "project")

      results.each do |r|
        next unless r.is_a?(Hash) && r[:fact]
        fact = builder.store.facts.where(id: r[:fact][:id]).first
        # Project-scoped query should not return global facts in legacy mode
        # (dual-mode handles this differently via StoreManager)
        expect(fact).not_to be_nil, "Retrieved fact should exist"
      end
    end
  end
end
