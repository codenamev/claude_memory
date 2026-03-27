# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "Claude Code Extraction Quality", :benchmark do
  include BenchmarkHelpers::ExtractionMetrics
  include BenchmarkHelpers::DistillationSetup

  let(:distiller) { ClaudeMemory::Distill::NullDistiller.new }
  let(:original_cases) { BenchmarkHelpers::DatasetLoader.load_extraction_cases }
  let(:llm_cases) { BenchmarkHelpers::DatasetLoader.load_llm_extraction_cases }
  let(:all_cases) { original_cases + llm_cases }

  context "NullDistiller baseline on all cases" do
    it "reports NullDistiller extraction metrics across original + LLM cases" do
      entity_precisions = []
      entity_recalls = []
      fact_precisions = []
      fact_recalls = []
      decision_recalls = []
      failures = []

      all_cases.each do |tc|
        extraction = distiller.distill(tc["text"])
        expected = tc.fetch("expected", {})

        # Entity metrics
        exp_entities = expected.fetch("entities", [])
        ext_entities = extraction.entities.map { |e| {type: e[:type], name: e[:name]} }
        ep = extraction_precision(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }
        er = extraction_recall(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }
        entity_precisions << ep
        entity_recalls << er

        # Fact metrics (support both exact and _contains matching)
        exp_facts = expected.fetch("facts", [])
        ext_facts = extraction.facts.map { |f|
          h = {predicate: f[:predicate], object: f[:object]}
          h[:scope_hint] = f[:scope_hint] if f[:scope_hint]
          h
        }
        fp = extraction_precision(ext_facts, exp_facts) { |e, exp| matches?(e, exp) }
        fr = extraction_recall(ext_facts, exp_facts) { |e, exp| matches?(e, exp) }
        fact_precisions << fp
        fact_recalls << fr

        # Decision metrics (LLM cases may have expected decisions)
        exp_decisions = expected.fetch("decisions", [])
        ext_decisions = extraction.decisions.map { |d| {title: d[:title]} }
        dr = extraction_recall(ext_decisions, exp_decisions) { |e, exp| matches?(e, exp) }
        decision_recalls << dr

        # Track failures
        if fr < 1.0 && exp_facts.any?
          missed = exp_facts.reject { |exp| ext_facts.any? { |e| matches?(e, exp) } }
          if missed.any?
            missed_desc = missed.map { |m|
              pred = m["predicate"] || m["predicate_contains"] || m[:predicate]
              obj = m["object"] || m["object_contains"] || m[:object]
              "#{pred}:#{obj}"
            }.join(", ")
            failures << "MISS #{tc["id"]}: facts [#{missed_desc}]"
          end
        end

        if dr < 1.0 && exp_decisions.any?
          failures << "MISS #{tc["id"]}: decisions not extracted"
        end
      end

      # Compute averages
      avg_ep = entity_precisions.sum / entity_precisions.size
      avg_er = entity_recalls.sum / entity_recalls.size
      entity_f1 = f1_score(avg_ep, avg_er)
      avg_fp = fact_precisions.sum / fact_precisions.size
      avg_fr = fact_recalls.sum / fact_recalls.size
      fact_f1 = f1_score(avg_fp, avg_fr)
      avg_dr = decision_recalls.sum / decision_recalls.size

      # Separate metrics for original vs LLM cases
      llm_fact_recalls = llm_cases.map { |tc|
        exp = tc.fetch("expected", {}).fetch("facts", [])
        ext = distiller.distill(tc["text"]).facts.map { |f|
          h = {predicate: f[:predicate], object: f[:object]}
          h[:scope_hint] = f[:scope_hint] if f[:scope_hint]
          h
        }
        extraction_recall(ext, exp) { |e, expf| matches?(e, expf) }
      }
      avg_llm_fr = llm_fact_recalls.sum / llm_fact_recalls.size

      # Report
      puts "\n  NullDistiller Baseline (#{all_cases.size} total cases):"
      puts "    Entity  - Precision: #{avg_ep.round(3)}  Recall: #{avg_er.round(3)}  F1: #{entity_f1.round(3)}"
      puts "    Fact    - Precision: #{avg_fp.round(3)}  Recall: #{avg_fr.round(3)}  F1: #{fact_f1.round(3)}"
      puts "    Decision Recall: #{avg_dr.round(3)}"
      puts ""
      puts "    Original cases (#{original_cases.size}): Fact Recall: #{(fact_recalls.first(original_cases.size).sum / original_cases.size).round(3)}"
      puts "    LLM cases (#{llm_cases.size}):      Fact Recall: #{avg_llm_fr.round(3)}  (expected to be low)"
      puts ""

      if failures.any?
        puts "    Failures (#{failures.size}):"
        failures.first(10).each { |f| puts "      #{f}" }
        puts "      ... and #{failures.size - 10} more" if failures.size > 10
      end

      expect(all_cases.size).to be > 0
    end
  end

  context "Claude Code extraction", :eval_real do
    it "reports Claude extraction metrics and comparison with NullDistiller" do
      skip "Requires EVAL_MODE=real" unless ENV["EVAL_MODE"] == "real"
      skip "Real mode requires claude CLI" unless system("which claude > /dev/null 2>&1")

      claude_fact_recalls = []
      claude_fact_precisions = []
      claude_decision_recalls = []
      claude_entity_recalls = []
      null_fact_recalls = []
      null_decision_recalls = []
      failures = []

      all_cases.each do |tc|
        tmpdir = setup_tmpdir_with_mcp

        begin
          # Run Claude with extraction prompt
          runner = EvalHelpers::ClaudeCliRunner.new(
            working_dir: tmpdir,
            memory_enabled: true
          )
          result = runner.run(prompt: extraction_prompt(tc["text"]))

          expected = tc.fetch("expected", {})

          if result[:success]
            # Read what Claude stored in the database
            stored = read_stored_facts(tmpdir)
            stored_facts = stored[:facts]
            stored_entities = stored[:entities]

            # Map stored facts to matchable hashes
            ext_facts = stored_facts.map { |f|
              {predicate: f[:predicate].to_s, object: f[:object_literal].to_s}
            }
            exp_facts = expected.fetch("facts", [])
            fp = extraction_precision(ext_facts, exp_facts) { |e, exp| matches?(e, exp) }
            fr = extraction_recall(ext_facts, exp_facts) { |e, exp| matches?(e, exp) }
            claude_fact_precisions << fp
            claude_fact_recalls << fr

            # Entity metrics
            ext_entities = stored_entities.map { |e| {type: e[:type].to_s, name: e[:name].to_s} }
            exp_entities = expected.fetch("entities", [])
            er = extraction_recall(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }
            claude_entity_recalls << er

            # Decision metrics — check if any stored fact looks like a decision
            exp_decisions = expected.fetch("decisions", [])
            ext_decisions = stored_facts.select { |f|
              f[:predicate].to_s.include?("decision") ||
                f[:predicate].to_s.include?("convention")
            }.map { |f| {title: f[:object_literal].to_s} }
            dr = extraction_recall(ext_decisions, exp_decisions) { |e, exp| matches?(e, exp) }
            claude_decision_recalls << dr

            if fr < 1.0 && exp_facts.any?
              missed = exp_facts.reject { |exp_f| ext_facts.any? { |e| matches?(e, exp_f) } }
              if missed.any?
                failures << "MISS #{tc["id"]}: #{missed.size} facts not stored by Claude"
              end
            end
          else
            puts "    ERROR #{tc["id"]}: #{result[:error]}"
            claude_fact_recalls << 0.0
            claude_fact_precisions << 0.0
            claude_decision_recalls << 0.0
            claude_entity_recalls << 0.0
          end

          # NullDistiller comparison
          extraction = distiller.distill(tc["text"])
          ext_facts_null = extraction.facts.map { |f|
            h = {predicate: f[:predicate], object: f[:object]}
            h[:scope_hint] = f[:scope_hint] if f[:scope_hint]
            h
          }
          exp_facts = expected.fetch("facts", [])
          null_fr = extraction_recall(ext_facts_null, exp_facts) { |e, exp| matches?(e, exp) }
          null_fact_recalls << null_fr

          exp_decisions = expected.fetch("decisions", [])
          ext_decisions_null = extraction.decisions.map { |d| {title: d[:title]} }
          null_dr = extraction_recall(ext_decisions_null, exp_decisions) { |e, exp| matches?(e, exp) }
          null_decision_recalls << null_dr
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end

      # Compute averages
      avg_claude_fr = claude_fact_recalls.sum / claude_fact_recalls.size
      avg_claude_fp = claude_fact_precisions.sum / claude_fact_precisions.size
      claude_fact_f1 = f1_score(avg_claude_fp, avg_claude_fr)
      avg_claude_dr = claude_decision_recalls.sum / claude_decision_recalls.size
      avg_claude_er = claude_entity_recalls.sum / claude_entity_recalls.size

      avg_null_fr = null_fact_recalls.sum / null_fact_recalls.size
      avg_null_dr = null_decision_recalls.sum / null_decision_recalls.size

      # Print comparison table
      puts "\n  " + "=" * 56
      puts "  Extraction Quality Comparison (#{all_cases.size} cases)"
      puts "  " + "=" * 56
      puts ""
      puts "  #{"Metric".ljust(25)} #{"NullDistiller".ljust(15)} #{"Claude Code".ljust(15)}"
      puts "  " + "-" * 56
      puts "  #{"Fact Recall".ljust(25)} #{avg_null_fr.round(3).to_s.ljust(15)} #{avg_claude_fr.round(3)}"
      puts "  #{"Fact Precision".ljust(25)} #{"—".ljust(15)} #{avg_claude_fp.round(3)}"
      puts "  #{"Fact F1".ljust(25)} #{"—".ljust(15)} #{claude_fact_f1.round(3)}"
      puts "  #{"Decision Recall".ljust(25)} #{avg_null_dr.round(3).to_s.ljust(15)} #{avg_claude_dr.round(3)}"
      puts "  #{"Entity Recall".ljust(25)} #{"—".ljust(15)} #{avg_claude_er.round(3)}"
      puts ""

      if failures.any?
        puts "  Claude Failures (#{failures.size}):"
        failures.first(10).each { |f| puts "    #{f}" }
        puts "    ... and #{failures.size - 10} more" if failures.size > 10
      end

      expect(all_cases.size).to be > 0
    end
  end
end
