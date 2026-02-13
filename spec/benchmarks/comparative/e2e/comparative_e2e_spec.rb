# frozen_string_literal: true

require_relative "../comparative_helper"

RSpec.describe "Comparative E2E", :comparative, :eval_real, :slow do
  include ComparativeHelpers::ComparativeSetup
  include EvalHelpers::ScoringHelpers

  let(:e2e_scenarios) { BenchmarkHelpers::DatasetLoader.load_e2e_scenarios }
  let(:adapters) { ComparativeHelpers.e2e_adapters }

  # Select 10 scenarios: 2 per ability category
  let(:comparative_scenarios) do
    abilities = e2e_scenarios.group_by { |s| s["ability"] }
    abilities.flat_map { |_ability, scenarios| scenarios.first(2) }
  end

  def eval_mode
    ENV["EVAL_MODE"] || "stub"
  end

  def project_root
    File.expand_path("../../../..", __dir__)
  end

  describe "memory backend comparison" do
    it "compares E2E acceptance rates across adapters" do
      skip "Skipped in stub mode (set EVAL_MODE=real)" if eval_mode == "stub"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")
      skip "No E2E scenarios" if comparative_scenarios.empty?

      adapter_results = {}
      adapters.each { |a| adapter_results[a.name] = {passed: 0, scores: [], total: 0} }

      comparative_scenarios.each do |scenario|
        adapters.each do |adapter|
          scenario_tmpdir = Dir.mktmpdir("comparative_e2e_#{adapter.name.gsub(/\W/, "_")}_#{scenario["id"]}")

          begin
            # Set up adapter's memory in this tmpdir
            adapter.setup(facts_for_scenario(scenario), scenario_tmpdir)
            adapter.setup_for_claude(scenario_tmpdir)

            # Run prompt through real Claude
            runner = EvalHelpers::ClaudeCliRunner.new(
              working_dir: scenario_tmpdir,
              memory_enabled: true
            )

            result = runner.run(prompt: scenario["prompt"])
            adapter_results[adapter.name][:total] += 1

            if result[:success]
              criteria = EvalHelpers::SimpleAcceptanceCriteria.new(
                required_keywords: scenario["acceptance_keywords"],
                threshold: scenario["threshold"]
              )

              evaluation = criteria.evaluate(result[:result])

              # Check rejection keywords
              rejection_clean = true
              if scenario["rejection_keywords"]&.any?
                rejection_clean = scenario["rejection_keywords"].none? { |kw|
                  result[:result].downcase.include?(kw.downcase)
                }
              end

              if evaluation.passed? && rejection_clean
                adapter_results[adapter.name][:passed] += 1
              end
              adapter_results[adapter.name][:scores] << evaluation.score

              status = (evaluation.passed? && rejection_clean) ? "PASS" : "FAIL"
              puts "    #{adapter.name} | #{scenario["id"]}: #{status} (score=#{evaluation.score.round(2)})"
            else
              adapter_results[adapter.name][:scores] << 0.0
              puts "    #{adapter.name} | #{scenario["id"]}: ERROR #{result[:error]}"
            end
          ensure
            adapter.teardown
            FileUtils.rm_rf(scenario_tmpdir)
          end
        end
      end

      # Report results
      puts "\n  E2E COMPARATIVE RESULTS:"
      adapters.each do |adapter|
        r = adapter_results[adapter.name]
        next if r[:total] == 0

        acceptance_rate = r[:passed].to_f / r[:total]
        avg_score = r[:scores].empty? ? 0.0 : r[:scores].sum / r[:scores].size

        reporter.add_e2e_results(adapter.name, {
          acceptance_rate: acceptance_rate,
          avg_score: avg_score,
          scenarios: r[:total]
        })

        puts "    #{adapter.name}: #{r[:passed]}/#{r[:total]} " \
          "(#{(acceptance_rate * 100).round(0)}%) avg_score=#{avg_score.round(3)}"
      end

      puts reporter.terminal_report
    end
  end

  describe "stub mode validation" do
    it "validates comparative E2E structure" do
      expect(comparative_scenarios.size).to be <= 10,
        "Comparative E2E should use at most 10 scenarios for cost efficiency"
      expect(comparative_scenarios.size).to be >= 2,
        "Should have at least 2 scenarios"

      abilities = comparative_scenarios.map { |s| s["ability"] }.uniq
      puts "  Comparative E2E: #{comparative_scenarios.size} scenarios across #{abilities.size} abilities"
      puts "  Abilities: #{abilities.join(", ")}"
      puts "  Available E2E adapters: #{adapters.map(&:name).join(", ")}"
    end
  end

  private

  # Build fact list for a scenario
  def facts_for_scenario(scenario)
    (scenario["facts_to_load"] || []).map { |f| normalize_fact_data(f) }
  end

  def normalize_fact_data(fact_data)
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
