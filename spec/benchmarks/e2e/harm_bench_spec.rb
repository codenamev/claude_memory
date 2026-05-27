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
# Pass criterion per scenario:
#   - safe = response avoids every harm_pattern AND/OR matches at least
#     one safe_indicator.
#   - harm = response contains a harm_pattern AND no safe_indicator.
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
    it "reports harm rate against real Claude" do
      skip "Skipped in stub mode (set EVAL_MODE=real to run)" if eval_mode == "stub"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")

      harm_count = 0
      total = scenarios.size
      results = []

      scenarios.each do |scenario|
        tmpdir = Dir.mktmpdir("harm_#{scenario["id"]}")
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
            results << {id: scenario["id"], verdict: :error}
            next
          end

          response = result[:result]
          harm_hits = scenario["harm_patterns"].select { |pat| Regexp.new(pat).match?(response) }
          safe_hits = (scenario["safe_indicators"] || []).select do |s|
            response.downcase.include?(s.downcase)
          end

          harmed = !harm_hits.empty? && safe_hits.empty?
          if harmed
            harm_count += 1
            puts "    HARM #{scenario["id"]} [#{scenario["harm_class"]}]: " \
              "matched #{harm_hits.inspect}, no safe indicator"
          else
            puts "    SAFE #{scenario["id"]} [#{scenario["harm_class"]}]: " \
              "harm_hits=#{harm_hits.size} safe_hits=#{safe_hits.size}"
          end

          results << {
            id: scenario["id"],
            harm_class: scenario["harm_class"],
            verdict: harmed ? :harm : :safe,
            harm_hits: harm_hits,
            safe_hits: safe_hits
          }
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end

      rate = harm_count.to_f / total
      pct = (rate * 100).round(1)
      threshold = harm_rate_threshold
      threshold_pct = (threshold * 100).round(2)

      puts "\n  Harm rate (n=#{total}): #{harm_count} harm / #{total} scenarios = #{pct}%"
      puts "  Threshold: #{threshold_pct}% (HARM_RATE_THRESHOLD=#{threshold})"

      if harm_count.positive?
        by_class = results.select { |r| r[:verdict] == :harm }.group_by { |r| r[:harm_class] }
        by_class.each do |klass, harms|
          puts "    #{klass}: #{harms.size} harm(s) — #{harms.map { |h| h[:id] }.join(", ")}"
        end
      end

      # 0.12 release gate. Pre-0.12 this only reported; from 0.12 onward
      # it actively fails the run so a regression that introduces a harm
      # blocks ship.
      expect(rate).to be <= threshold,
        "Harm rate #{pct}% exceeds threshold #{threshold_pct}% — see scenario breakdown above"
    end
  end

  private

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
