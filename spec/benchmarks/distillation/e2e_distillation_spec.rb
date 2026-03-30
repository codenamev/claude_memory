# frozen_string_literal: true

require_relative "../benchmark_helper"

# Broader keyword synonyms for loosened scoring.
# Maps acceptance keywords to additional alternatives that indicate
# the same concept was understood, even if exact class names differ.
module E2EDistillationHelpers
  KEYWORD_SYNONYMS = {
    "Result" => ["result type", "result object", "error handling", "monad"],
    "Success" => ["success", "ok", "right"],
    "Failure" => ["failure", "error", "left"],
    "immutable" => ["frozen", "freeze", "immutability"],
    "null object" => ["null pattern", "nullobject", "nullfact", "nullexplanation"],
    "dependency injection" => ["constructor injection", "inject", "di pattern"],
    "dataset" => ["dataset method", "sequel dataset", "query builder"]
  }.freeze

  # Compute a loosened keyword score: if the response mentions any keyword
  # or its synonyms, count it as a hit.
  def loosened_keyword_score(response_text, keywords)
    return 1.0 if keywords.empty?

    response_lower = response_text.downcase
    found = keywords.count { |kw|
      kw_lower = kw.downcase
      next true if response_lower.include?(kw_lower)

      # Check synonyms
      synonyms = KEYWORD_SYNONYMS[kw] || []
      synonyms.any? { |syn| response_lower.include?(syn.downcase) }
    }
    found.to_f / keywords.size
  end
end

RSpec.describe "E2E Distillation Recall", :benchmark, :eval_real do
  include BenchmarkHelpers::DistillationSetup
  include EvalHelpers::ScoringHelpers
  include E2EDistillationHelpers

  let(:e2e_scenarios) { BenchmarkHelpers::DatasetLoader.load_e2e_scenarios }

  # Select information_extraction scenarios — these test whether stored facts
  # can be recalled, making them ideal for measuring distillation quality.
  let(:extraction_scenarios) {
    e2e_scenarios
      .select { |s| s["ability"] == "information_extraction" }
      .first(5)
  }

  describe "distilled memory vs baseline" do
    it "measures recall improvement from Claude distillation" do
      skip "Requires EVAL_MODE=real" unless ENV["EVAL_MODE"] == "real"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")
      skip "No information_extraction scenarios" if extraction_scenarios.empty?

      memory_scores = []
      memory_loosened_scores = []
      baseline_scores = []
      results = []

      extraction_scenarios.each do |scenario|
        tmpdir = setup_tmpdir_with_mcp

        begin
          # Phase A: Feed transcript to Claude for distillation
          distill_runner = EvalHelpers::ClaudeCliRunner.new(
            working_dir: tmpdir,
            memory_enabled: true,
            allowed_tools: EvalHelpers::ClaudeCliRunner::MEMORY_TOOLS
          )
          distill_result = distill_runner.run(
            prompt: distillation_prompt(scenario)
          )

          unless distill_result[:success]
            puts "    DISTILL ERROR #{scenario["id"]}: #{distill_result[:error]}"
            next
          end

          # Phase B: Query Claude with the question (memory-enabled)
          query_runner = EvalHelpers::ClaudeCliRunner.new(
            working_dir: tmpdir,
            memory_enabled: true,
            allowed_tools: EvalHelpers::ClaudeCliRunner::MEMORY_TOOLS
          )
          memory_result = query_runner.run(prompt: scenario["prompt"])

          if memory_result[:success]
            keywords = scenario["acceptance_keywords"]
            criteria = EvalHelpers::SimpleAcceptanceCriteria.new(
              required_keywords: keywords,
              threshold: scenario.fetch("threshold", 0.75)
            )
            evaluation = criteria.evaluate(memory_result[:result])
            memory_scores << evaluation.score

            # Loosened score with synonym matching
            loosened = loosened_keyword_score(memory_result[:result], keywords)
            memory_loosened_scores << loosened

            # Check rejection keywords
            rejection_clean = true
            if scenario["rejection_keywords"]&.any?
              rejection_clean = scenario["rejection_keywords"].none? do |keyword|
                memory_result[:result].downcase.include?(keyword.downcase)
              end
            end

            results << {
              id: scenario["id"],
              name: scenario["name"],
              memory_score: evaluation.score,
              memory_loosened: loosened,
              memory_passed: (evaluation.passed? || loosened >= scenario.fetch("threshold", 0.75)) && rejection_clean,
              memory_missing: evaluation.missing
            }
          else
            puts "    QUERY ERROR #{scenario["id"]}: #{memory_result[:error]}"
          end
        ensure
          FileUtils.rm_rf(tmpdir)
        end

        # Baseline run (no memory, clean tmpdir)
        baseline_tmpdir = Dir.mktmpdir("distill-baseline")
        begin
          baseline_runner = EvalHelpers::ClaudeCliRunner.new(
            working_dir: baseline_tmpdir,
            memory_enabled: false
          )
          baseline_result = baseline_runner.run(prompt: scenario["prompt"])

          if baseline_result[:success]
            criteria = EvalHelpers::SimpleAcceptanceCriteria.new(
              required_keywords: scenario["acceptance_keywords"],
              threshold: 0.0
            )
            baseline_eval = criteria.evaluate(baseline_result[:result])
            baseline_scores << baseline_eval.score

            # Update results with baseline
            if results.last && results.last[:id] == scenario["id"]
              results.last[:baseline_score] = baseline_eval.score
            end
          end
        ensure
          FileUtils.rm_rf(baseline_tmpdir)
        end
      end

      # Report
      puts "\n  " + "=" * 60
      puts "  E2E Distillation Recall (#{extraction_scenarios.size} scenarios)"
      puts "  " + "=" * 60
      puts ""

      memory_passed = 0
      results.each do |r|
        status = r[:memory_passed] ? "PASS" : "FAIL"
        memory_passed += 1 if r[:memory_passed]
        baseline_str = r[:baseline_score] ? r[:baseline_score].round(2).to_s : "—"
        puts format("    %s %-20s  memory=%.2f  loosened=%.2f  baseline=%s",
          status, r[:id], r[:memory_score], r[:memory_loosened], baseline_str)
        if r[:memory_missing]&.any? && !r[:memory_passed]
          puts "      Missing: #{r[:memory_missing].join(", ")}"
        end
      end

      puts ""
      if memory_scores.any?
        avg_memory = memory_scores.sum / memory_scores.size
        avg_loosened = memory_loosened_scores.sum / memory_loosened_scores.size
        puts "    Memory pass rate: #{memory_passed}/#{results.size}"
        puts "    Avg memory score (exact): #{avg_memory.round(3)}"
        puts "    Avg memory score (loosened): #{avg_loosened.round(3)}"
      end

      if baseline_scores.any?
        avg_baseline = baseline_scores.sum / baseline_scores.size
        puts "    Avg baseline score: #{avg_baseline.round(3)}"

        if memory_scores.any?
          avg_memory = memory_scores.sum / memory_scores.size
          delta = avg_memory - avg_baseline
          sign = (delta >= 0) ? "+" : ""
          puts "    Delta (exact): #{sign}#{delta.round(3)}"

          avg_loosened = memory_loosened_scores.sum / memory_loosened_scores.size
          delta_loosened = avg_loosened - avg_baseline
          sign_loosened = (delta_loosened >= 0) ? "+" : ""
          puts "    Delta (loosened): #{sign_loosened}#{delta_loosened.round(3)}"
        end
      end

      # Soft assertion — distilled memory should help
      expect(results.size).to be > 0
    end
  end

  describe "stub mode validation" do
    it "validates LLM extraction dataset structure" do
      llm_cases = BenchmarkHelpers::DatasetLoader.load_llm_extraction_cases

      llm_cases.each do |tc|
        expect(tc["id"]).not_to be_nil, "Case must have an id"
        expect(tc["category"]).not_to be_nil, "Case must have a category"
        expect(tc["text"]).not_to be_nil, "Case must have text"
        expect(tc["expected"]).to be_a(Hash), "Case must have expected hash"
      end

      categories = llm_cases.group_by { |c| c["category"] }
      puts "\n  LLM Extraction Dataset: #{llm_cases.size} cases"
      categories.each { |cat, cases| puts "    #{cat}: #{cases.size}" }

      expect(llm_cases.size).to be >= 10
    end

    it "validates distillation scenarios are available" do
      expect(extraction_scenarios.size).to be > 0
      puts "\n  E2E Distillation: #{extraction_scenarios.size} scenarios selected"
      extraction_scenarios.each do |s|
        puts "    #{s["id"]}: #{s["name"]}"
      end
    end
  end
end
