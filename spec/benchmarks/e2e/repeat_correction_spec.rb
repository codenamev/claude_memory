# frozen_string_literal: true

require_relative "../benchmark_helper"

# Repeat-correction benchmark: measures whether memory propagates judgment
# across sessions. Each scenario represents a correction that was already
# given in a past session (pre-loaded as a memory fact). The prompt would
# re-trigger the bad pattern if memory failed. Pass = no violation_patterns
# match in the response. Fail = the same correction would need to be given
# again.
#
# See docs/improvements.md #32 and spec/benchmarks/dataset/repeat_correction_scenarios.yml.
RSpec.describe "RepeatCorrectionBench", :benchmark, :eval_real, :slow do
  include BenchmarkHelpers::BenchmarkSetup

  let(:scenarios) { BenchmarkHelpers::DatasetLoader.load_repeat_correction_scenarios }

  def eval_mode
    ENV["EVAL_MODE"] || "stub"
  end

  describe "structure validation" do
    it "validates scenario schema and loadability" do
      expect(scenarios).not_to be_empty, "Must have at least one scenario"

      scenarios.each do |scenario|
        expect(scenario["id"]).to be_a(String), "Scenario must have a string id"
        expect(scenario["name"]).to be_a(String), "Scenario must have a name"
        expect(scenario["prompt"]).to be_a(String), "Scenario must have a prompt"
        expect(scenario["memory_facts"]).to be_a(Array), "Must have memory_facts array"
        expect(scenario["memory_facts"]).not_to be_empty, "memory_facts can't be empty"
        expect(scenario["violation_patterns"]).to be_a(Array), "Must have violation_patterns"
        expect(scenario["violation_patterns"]).not_to be_empty, "violation_patterns can't be empty"

        # Every violation pattern must compile as a regex
        scenario["violation_patterns"].each do |pat|
          expect { Regexp.new(pat) }.not_to raise_error,
            "Scenario #{scenario["id"]}: pattern #{pat.inspect} is not a valid regex"
        end

        # Facts must be loadable via the same builder the e2e spec uses
        tmpdir = Dir.mktmpdir("repeat_correction_validate_#{scenario["id"]}")
        db_path = File.join(tmpdir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(db_path))
        begin
          builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path)
          scenario["memory_facts"].each do |fact|
            builder.load_fact(normalize_fact(fact, scenario["id"]))
          end
          expect(builder.store.facts.count).to eq(scenario["memory_facts"].size)
          builder.close
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end

      puts "\n  Validated #{scenarios.size} repeat-correction scenarios"
      scenarios.each { |s| puts "    - #{s["id"]}: #{s["name"]}" }
    end
  end

  describe "memory-enabled responses" do
    it "checks that known corrections are not repeated" do
      skip "Skipped in stub mode" if eval_mode == "stub"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")

      passed = 0
      total = scenarios.size

      scenarios.each do |scenario|
        tmpdir = Dir.mktmpdir("repeat_correction_#{scenario["id"]}")
        db_path = File.join(tmpdir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(db_path))

        begin
          builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path)
          scenario["memory_facts"].each { |f| builder.load_fact(normalize_fact(f, scenario["id"])) }
          builder.close

          runner = EvalHelpers::ClaudeCliRunner.new(
            working_dir: tmpdir,
            memory_enabled: true
          )
          result = runner.run(prompt: scenario["prompt"])

          unless result[:success]
            puts "    ERROR #{scenario["id"]}: #{result[:error]}"
            next
          end

          violations = scenario["violation_patterns"].select do |pat|
            Regexp.new(pat).match?(result[:result])
          end
          mentions = (scenario["expected_mentions"] || []).select do |m|
            result[:result].downcase.include?(m.downcase)
          end

          if violations.empty?
            passed += 1
            puts "    PASS #{scenario["id"]}: #{scenario["name"]} (mentions=#{mentions.size}/#{(scenario["expected_mentions"] || []).size})"
          else
            puts "    FAIL #{scenario["id"]}: #{scenario["name"]}"
            puts "      Violations: #{violations.join(", ")}"
            puts "      Correction should have been prevented by memory"
          end
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end

      pct = (passed.to_f / total * 100).round(0)
      puts "\n  Repeat-correction pass rate: #{passed}/#{total} (#{pct}%)"

      # No hard assertion on pass rate yet — this metric is a trend signal.
      # Track it over releases; tighten the bar once we have baseline data.
      expect(passed).to be >= 0
    end
  end

  private

  # Map the scenario's compact memory_fact shape onto the BenchmarkFixtureBuilder
  # fact schema. We stamp a deterministic id so provenance links are stable if
  # we ever extend the scenarios with supersedes/ references.
  def normalize_fact(fact_data, scenario_id)
    {
      "id" => fact_data["id"] || "#{scenario_id}_#{fact_data["predicate"]}",
      "subject" => fact_data["subject"] || "claude_memory",
      "predicate" => fact_data["predicate"],
      "object" => fact_data["object"],
      "text" => fact_data["text"] || fact_data["object"],
      "fts_keywords" => fact_data["fts_keywords"],
      "scope" => fact_data["scope"] || "project",
      "status" => fact_data["status"] || "active",
      "strength" => fact_data["strength"] || "stated",
      "confidence" => fact_data["confidence"] || 1.0
    }
  end
end
