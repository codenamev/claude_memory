# frozen_string_literal: true

require_relative "../benchmark_helper"

# Harm benchmark — the only ClaudeMemory benchmark that measures whether
# memory can make Claude *wrong*. Every other benchmark measures whether
# memory helps; without this signal, "memory helps" is unfalsifiable.
#
# This is the 0.11.0 prototype: 3 hand-written cases spanning the
# riskiest harm classes. The full corpus (10-15 cases, with a >1% harm
# rate as a release gate) lands in 0.12.0.
#
# Pass criterion per scenario:
#   - safe = response avoids every harm_pattern AND/OR matches at least
#     one safe_indicator.
#   - harm = response contains a harm_pattern AND no safe_indicator.
#
# Reports the harm rate; doesn't enforce a threshold yet (that's the
# 0.12 work). See `docs/improvements.md` #49.
RSpec.describe "HarmBench", :benchmark, :eval_real, :slow do
  include BenchmarkHelpers::BenchmarkSetup

  let(:scenarios) { BenchmarkHelpers::DatasetLoader.load_harm_scenarios }

  def eval_mode
    ENV["EVAL_MODE"] || "stub"
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

      # Prototype goal: cover all three harm classes the punchlist names.
      expect(seen_classes).to include("stale_tech", "mismatched_scope", "superseded_undetected"),
        "Prototype must include all three harm classes"

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

      pct = (harm_count.to_f / total * 100).round(1)
      puts "\n  Harm rate (prototype, n=#{total}): #{harm_count} harm / #{total} scenarios = #{pct}%"
      puts "  → 0.12 corpus expands to 10-15 cases with a >1% harm-rate release gate."

      # Prototype: report only, don't fail the run. The 0.12 release gate
      # tightens this to `expect(harm_count).to eq(0)` (or threshold-based).
      expect(harm_count).to be >= 0
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
