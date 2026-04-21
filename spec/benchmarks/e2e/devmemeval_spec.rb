# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "DevMemEval", :benchmark, :eval_real, :slow do
  include BenchmarkHelpers::BenchmarkSetup
  include BenchmarkHelpers::RelevanceMetrics
  include EvalHelpers::ScoringHelpers

  let(:e2e_scenarios) { BenchmarkHelpers::DatasetLoader.load_e2e_scenarios }

  # Group scenarios by ability category
  let(:abilities) { e2e_scenarios.group_by { |s| s["ability"] } }

  def project_root
    File.expand_path("../../..", __dir__)
  end

  def eval_mode
    ENV["EVAL_MODE"] || "stub"
  end

  describe "memory-enabled responses" do
    %w[information_extraction multi_session_reasoning temporal_reasoning knowledge_update abstention].each do |ability|
      context "#{ability} scenarios" do
        it "evaluates #{ability} with real Claude" do
          skip "Skipped in stub mode" if eval_mode == "stub"
          skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")

          scenarios = e2e_scenarios.select { |s| s["ability"] == ability }
          skip "No #{ability} scenarios" if scenarios.empty?

          passed = 0
          total = scenarios.size
          ratios = []

          scenarios.each do |scenario|
            scenario_tmpdir = Dir.mktmpdir("devmemeval_#{scenario["id"]}")
            scenario_db_path = File.join(scenario_tmpdir, ".claude/memory.sqlite3")
            FileUtils.mkdir_p(File.dirname(scenario_db_path))

            begin
              # Load fixture facts
              builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(scenario_db_path)

              facts_to_load = scenario["facts_to_load"]
              facts_to_load.each do |fact_data|
                builder.load_fact(normalize_fact_data(fact_data))
              end
              builder.close

              # Reconstruct what the SessionStart hook would have injected
              # against this scenario's DB. We re-run ContextInjector locally
              # (same DB state → same injection) instead of scraping the
              # running Claude process — close enough for a trend metric.
              injected_subjects = capture_injected_subjects(scenario_db_path, scenario_tmpdir)

              # Run prompt through real Claude with memory
              runner = EvalHelpers::ClaudeCliRunner.new(
                working_dir: scenario_tmpdir,
                memory_enabled: true
              )

              result = runner.run(prompt: scenario["prompt"])

              if result[:success]
                ratio = relevance_ratio(injected_subjects, result[:result])
                ratios << ratio
                # Evaluate response
                criteria = EvalHelpers::SimpleAcceptanceCriteria.new(
                  required_keywords: scenario["acceptance_keywords"],
                  threshold: scenario["threshold"]
                )

                evaluation = criteria.evaluate(result[:result])

                # Also check rejection keywords
                rejection_clean = true
                if scenario["rejection_keywords"]&.any?
                  rejection_clean = scenario["rejection_keywords"].none? do |keyword|
                    result[:result].downcase.include?(keyword.downcase)
                  end
                end

                if evaluation.passed? && rejection_clean
                  passed += 1
                  puts "    PASS #{scenario["id"]}: #{scenario["name"]} (score=#{evaluation.score.round(2)}, relevance=#{ratio.round(2)})"
                else
                  puts "    FAIL #{scenario["id"]}: #{scenario["name"]}"
                  puts "      Score: #{evaluation.score.round(2)} (threshold: #{scenario["threshold"]}, relevance=#{ratio.round(2)})"
                  puts "      Missing: #{evaluation.missing.join(", ")}" if evaluation.missing.any?
                  puts "      Rejection violation" unless rejection_clean
                end
              else
                puts "    ERROR #{scenario["id"]}: #{result[:error]}"
              end
            ensure
              FileUtils.rm_rf(scenario_tmpdir)
            end
          end

          puts "  #{ability}: #{passed}/#{total} (#{(passed.to_f / total * 100).round(0)}%)"
          if ratios.any?
            avg_ratio = ratios.sum / ratios.size
            puts "    avg relevance ratio: #{avg_ratio.round(3)} (facts_referenced / facts_injected across #{ratios.size} scenarios)"
          end

          # Expect at least 50% pass rate per ability
          expect(passed).to be >= (total * 0.5).ceil,
            "#{ability}: #{passed}/#{total} passed, expected at least 50%"
        end
      end
    end
  end

  describe "baseline comparison" do
    it "compares memory-enabled vs baseline responses" do
      skip "Skipped in stub mode" if eval_mode == "stub"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")

      # Run a subset of scenarios for cost efficiency
      sample_scenarios = e2e_scenarios
        .select { |s| s["ability"] == "information_extraction" }
        .first(3)

      skip "No extraction scenarios for baseline comparison" if sample_scenarios.empty?

      memory_scores = []
      baseline_scores = []

      sample_scenarios.each do |scenario|
        # Memory-enabled run
        memory_tmpdir = Dir.mktmpdir("devmemeval_memory_#{scenario["id"]}")
        memory_db_path = File.join(memory_tmpdir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(memory_db_path))

        begin
          builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(memory_db_path)
          scenario["facts_to_load"].each { |f| builder.load_fact(normalize_fact_data(f)) }
          builder.close

          memory_runner = EvalHelpers::ClaudeCliRunner.new(
            working_dir: memory_tmpdir,
            memory_enabled: true
          )
          memory_result = memory_runner.run(prompt: scenario["prompt"])

          if memory_result[:success]
            criteria = EvalHelpers::SimpleAcceptanceCriteria.new(
              required_keywords: scenario["acceptance_keywords"],
              threshold: 0.0 # We want the score, not pass/fail
            )
            memory_scores << criteria.evaluate(memory_result[:result]).score
          end
        ensure
          FileUtils.rm_rf(memory_tmpdir)
        end

        # Baseline run (no memory)
        baseline_tmpdir = Dir.mktmpdir("devmemeval_baseline_#{scenario["id"]}")
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
            baseline_scores << criteria.evaluate(baseline_result[:result]).score
          end
        ensure
          FileUtils.rm_rf(baseline_tmpdir)
        end
      end

      if memory_scores.any? && baseline_scores.any?
        avg_memory = memory_scores.sum / memory_scores.size
        avg_baseline = baseline_scores.sum / baseline_scores.size
        delta = avg_memory - avg_baseline

        puts "\n  Baseline Comparison (#{sample_scenarios.size} scenarios):"
        puts "    Memory-enabled:  #{avg_memory.round(3)}"
        puts "    Baseline:        #{avg_baseline.round(3)}"
        sign = (delta >= 0) ? "+" : ""
        puts "    Delta:           #{sign}#{delta.round(3)}"

        expect(avg_memory).to be >= avg_baseline,
          "Memory-enabled should score at least as well as baseline"
      end
    end
  end

  describe "stub mode validation" do
    it "validates scenario structure and fact loading" do
      e2e_scenarios.each do |scenario|
        expect(scenario["id"]).not_to be_nil, "Scenario must have an id"
        expect(scenario["ability"]).not_to be_nil, "Scenario must have an ability"
        expect(scenario["prompt"]).not_to be_nil, "Scenario must have a prompt"
        expect(scenario["acceptance_keywords"]).to be_a(Array), "Must have acceptance_keywords"
        expect(scenario["threshold"]).to be_a(Numeric), "Must have a numeric threshold"

        # Validate that facts can be loaded
        scenario_tmpdir = Dir.mktmpdir("devmemeval_validate_#{scenario["id"]}")
        scenario_db_path = File.join(scenario_tmpdir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(scenario_db_path))

        begin
          builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(scenario_db_path)
          facts_to_load = scenario["facts_to_load"]
          facts_to_load.each { |f| builder.load_fact(normalize_fact_data(f)) }

          # Verify facts were loaded
          fact_count = builder.store.facts.count
          expect(fact_count).to be >= facts_to_load.size,
            "Scenario #{scenario["id"]}: expected at least #{facts_to_load.size} facts, got #{fact_count}"

          builder.close
        ensure
          FileUtils.rm_rf(scenario_tmpdir)
        end
      end

      puts "\n  Validated #{e2e_scenarios.size} e2e scenarios"
      puts "  By ability:"
      abilities = e2e_scenarios.group_by { |s| s["ability"] }
      abilities.each { |ability, scenarios| puts "    #{ability}: #{scenarios.size}" }
    end
  end

  private

  # Reconstruct the subjects ContextInjector would emit for a given scenario.
  # We can't introspect the running Claude process, so we re-run the injector
  # locally against the same DB — same state in, same subjects out.
  def capture_injected_subjects(db_path, project_path)
    manager = ClaudeMemory::Store::StoreManager.new(
      global_db_path: db_path, # scenarios load into one DB; point global at it too
      project_db_path: db_path,
      project_path: project_path
    )
    manager.ensure_both!
    injector = ClaudeMemory::Hook::ContextInjector.new(manager, source: "startup")
    injector.generate_context
    injector.emitted_subjects.dup
  ensure
    manager&.close
  end

  # Normalize fact data from e2e scenario format to builder format
  def normalize_fact_data(fact_data)
    # e2e scenarios use string keys from YAML, normalize to expected format
    {
      "id" => fact_data["id"],
      "subject" => fact_data["subject"] || "test-project",
      "predicate" => fact_data["predicate"],
      "object" => fact_data["object"],
      "text" => fact_data["text"] || fact_data["object"],
      "fts_keywords" => fact_data["fts_keywords"],
      "scope" => fact_data["scope"] || "project",
      "status" => fact_data["status"] || "active",
      "valid_from" => fact_data["valid_from"],
      "valid_to" => fact_data["valid_to"],
      "strength" => fact_data["strength"] || "stated",
      "confidence" => fact_data["confidence"] || 1.0
    }
  end
end
