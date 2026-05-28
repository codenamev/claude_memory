# frozen_string_literal: true

require_relative "../benchmark_helper"

# Harm benchmark — the only ClaudeMemory benchmark that measures whether
# memory can make Claude *wrong*. Every other benchmark measures whether
# memory helps; without this signal, "memory helps" is unfalsifiable.
#
# 0.12.0 corpus: 13 hand-written cases across four harm classes
# (stale_tech, mismatched_scope, superseded_undetected,
# reference_material_as_fact). Release gate: HARM_RATE_THRESHOLD (default
# "0.01" = 1%) blocks the run if exceeded. See `docs/1_0_punchlist.md` #3.
#
# Pass criterion per scenario (single run):
#   - safe = response avoids every harm_pattern AND/OR matches at least
#     one safe_indicator.
#   - harm = response contains a harm_pattern AND no safe_indicator.
#
# Each scenario writes its `project_files` scaffold into the working
# directory so Claude sees a real project whose state contradicts the
# wrong memory fact (fixes the empty-tmpdir confound). Each scenario runs
# HARM_BENCH_RUNS times (default 3) and is scored harmed by MAJORITY vote
# over non-error runs, to absorb single-shot LLM nondeterminism.
REQUIRED_HARM_CLASSES = %w[stale_tech mismatched_scope superseded_undetected reference_material_as_fact].freeze

RSpec.describe "HarmBench", :benchmark, :eval_real, :slow do
  include BenchmarkHelpers::BenchmarkSetup

  let(:scenarios) { BenchmarkHelpers::DatasetLoader.load_harm_scenarios }

  def eval_mode
    ENV["EVAL_MODE"] || "stub"
  end

  def harm_rate_threshold
    Float(ENV.fetch("HARM_RATE_THRESHOLD", "0.01"))
  end

  def harm_bench_runs
    Integer(ENV.fetch("HARM_BENCH_RUNS", "3"))
  end

  describe "structure validation" do
    it "validates scenario schema and loadability" do
      expect(scenarios).not_to be_empty, "Must have at least one scenario"

      seen_classes = Set.new
      scenarios.each do |scenario|
        expect(scenario["id"]).to be_a(String), "Scenario must have a string id"
        expect(scenario["name"]).to be_a(String), "Scenario must have a name"
        expect(scenario["harm_class"]).to be_a(String), "Scenario must declare a harm_class"
        expect(scenario["prompt"]).to be_a(String), "Scenario must have a prompt"
        expect(scenario["memory_facts"]).to be_a(Array), "Must have memory_facts array"
        expect(scenario["memory_facts"]).not_to be_empty, "memory_facts can't be empty"
        expect(scenario["harm_patterns"]).to be_a(Array), "Must have harm_patterns"
        expect(scenario["harm_patterns"]).not_to be_empty, "harm_patterns can't be empty"
        expect(scenario["safe_indicators"]).to be_a(Array),
          "Must have safe_indicators (can be empty if pure-avoidance test)"
        expect(scenario["project_files"]).to be_a(Hash),
          "Scenario #{scenario["id"]} must ship a project_files scaffold"
        expect(scenario["project_files"]).not_to be_empty,
          "Scenario #{scenario["id"]} project_files can't be empty (fixes the empty-tmpdir confound)"

        scenario["harm_patterns"].each do |pat|
          expect { Regexp.new(pat) }.not_to raise_error,
            "Scenario #{scenario["id"]}: harm pattern #{pat.inspect} is not a valid regex"
        end

        seen_classes << scenario["harm_class"]

        # Facts must be loadable via the same builder the e2e spec uses
        tmpdir = Dir.mktmpdir("harm_validate_#{scenario["id"]}")
        db_path = File.join(tmpdir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(db_path))
        begin
          builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path)
          scenario["memory_facts"].each { |f| builder.load_fact(normalize_fact(f, scenario["id"])) }
          expect(builder.store.facts.count).to eq(scenario["memory_facts"].size)
          builder.close
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end

      # 0.12 corpus must cover all four harm classes the punchlist names.
      expect(seen_classes).to include(*REQUIRED_HARM_CLASSES),
        "Corpus must cover all four harm classes: #{REQUIRED_HARM_CLASSES.inspect}"

      # Corpus size discipline — must be in the 10-15 range the plan specifies.
      expect(scenarios.size).to be_between(10, 15),
        "Corpus size #{scenarios.size} outside the 10-15 range #1 requires"

      # Each class must have at least 2 scenarios so a single
      # bad/missing pattern doesn't trivially clear the gate.
      by_class = scenarios.group_by { |s| s["harm_class"] }
      REQUIRED_HARM_CLASSES.each do |klass|
        expect(by_class[klass]&.size.to_i).to be >= 2,
          "Class #{klass} needs ≥2 scenarios; got #{by_class[klass]&.size.to_i}"
      end

      puts "\n  Validated #{scenarios.size} harm scenarios across #{seen_classes.size} class(es)"
      scenarios.each { |s| puts "    - #{s["id"]} [#{s["harm_class"]}]: #{s["name"]}" }
    end
  end

  describe "memory-induced harm rate" do
    it "stays within the harm-rate threshold against real Claude (best-of-N)" do
      skip "Skipped in stub mode (set EVAL_MODE=real to run)" if eval_mode == "stub"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")

      runs = harm_bench_runs
      total = scenarios.size
      summaries = scenarios.map { |scenario| evaluate_scenario(scenario, runs) }

      harmed = summaries.select { |s| s[:harmed] }
      rate = harmed.size.to_f / total
      pct = (rate * 100).round(1)
      threshold = harm_rate_threshold
      threshold_pct = (threshold * 100).round(2)

      puts "\n  Harm rate (best-of-#{runs}, n=#{total}): " \
        "#{harmed.size} majority-harmed / #{total} scenarios = #{pct}%"
      puts "  Threshold: #{threshold_pct}% (HARM_RATE_THRESHOLD=#{threshold})"

      harmed.group_by { |s| s[:harm_class] }.each do |klass, list|
        list.each do |s|
          puts "    HARM #{s[:id]} [#{klass}]: #{s[:harm_n]}/#{s[:effective]} runs harmed"
        end
      end

      expect(rate).to be <= threshold,
        "Harm rate #{pct}% exceeds threshold #{threshold_pct}% — see scenario breakdown above"
    end
  end

  private

  # Runs a scenario `runs` times and scores it harmed by majority vote
  # over non-error runs. Returns a summary hash.
  def evaluate_scenario(scenario, runs)
    verdicts = Array.new(runs) { run_scenario_once(scenario) }
    harm_n = verdicts.count(:harm)
    error_n = verdicts.count(:error)
    effective = runs - error_n
    harmed = effective.positive? && harm_n > (effective / 2.0)

    label = harmed ? "HARM" : "SAFE"
    suffix = error_n.positive? ? " (#{error_n} error)" : ""
    puts "    #{label} #{scenario["id"]} [#{scenario["harm_class"]}]: " \
      "#{harm_n}/#{effective} harm#{suffix}"

    {
      id: scenario["id"],
      harm_class: scenario["harm_class"],
      harmed: harmed,
      harm_n: harm_n,
      effective: effective,
      error_n: error_n
    }
  end

  # One real-Claude run: fresh tmpdir, fixture DB, project scaffold, prompt.
  # Returns :harm, :safe, or :error.
  def run_scenario_once(scenario)
    tmpdir = Dir.mktmpdir("harm_#{scenario["id"]}")
    db_path = File.join(tmpdir, ".claude/memory.sqlite3")
    FileUtils.mkdir_p(File.dirname(db_path))

    builder = BenchmarkHelpers::BenchmarkFixtureBuilder.new(db_path)
    scenario["memory_facts"].each { |f| builder.load_fact(normalize_fact(f, scenario["id"])) }
    builder.close

    write_project_files(scenario, tmpdir)

    runner = EvalHelpers::ClaudeCliRunner.new(working_dir: tmpdir, memory_enabled: true)
    result = runner.run(prompt: scenario["prompt"])
    return :error unless result[:success]

    classify(scenario, result[:result])
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  # Writes the scenario's project_files scaffold into the working dir so
  # Claude sees real project state contradicting the wrong memory fact.
  def write_project_files(scenario, dir)
    (scenario["project_files"] || {}).each do |relpath, content|
      full = File.join(dir, relpath)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
  end

  def classify(scenario, response)
    harm_hits = scenario["harm_patterns"].select { |pat| Regexp.new(pat).match?(response) }
    safe_hits = (scenario["safe_indicators"] || []).select { |s| response.downcase.include?(s.downcase) }
    (!harm_hits.empty? && safe_hits.empty?) ? :harm : :safe
  end

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
      "confidence" => fact_data["confidence"] || 1.0,
      "valid_from" => fact_data["valid_from"]
    }
  end
end
