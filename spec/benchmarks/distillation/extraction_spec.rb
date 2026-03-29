# frozen_string_literal: true

require_relative "../benchmark_helper"

RSpec.describe "Distillation Extraction Accuracy", :benchmark do
  include BenchmarkHelpers::ExtractionMetrics

  let(:distiller) { ClaudeMemory::Distill::NullDistiller.new }
  let(:cases) { BenchmarkHelpers::DatasetLoader.load_extraction_cases }

  %w[entity fact].each do |category|
    context "#{category} cases" do
      it "measures extraction precision, recall, and F1" do
        category_cases = cases.select { |c| c["category"] == category }
        skip "No #{category} cases" if category_cases.empty?

        entity_precisions = []
        entity_recalls = []
        fact_precisions = []
        fact_recalls = []
        concept_recalls = []
        failures = []

        category_cases.each do |tc|
          extraction = distiller.distill(tc["text"])
          expected = tc.fetch("expected", {})

          # Entity metrics
          exp_entities = expected.fetch("entities", [])
          ext_entities = extraction.entities.map { |e| {type: e[:type], name: e[:name]} }
          ep = extraction_precision(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }
          er = extraction_recall(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }
          entity_precisions << ep
          entity_recalls << er

          # Fact metrics (include scope_hint if specified in expected)
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

          # Concept metrics
          concepts = tc.fetch("concepts", [])
          concept_recalls << null_distiller_concept_recall(extraction, concepts)

          # Track entity recall failures
          if er < 1.0
            missed = exp_entities.reject { |exp| ext_entities.any? { |e| matches?(e, exp) } }
            missed_names = missed.map { |m| m["name"] || m[:name] }.join(", ")
            failures << "MISS #{tc["id"]}: expected entities [#{missed_names}]" unless missed.empty?
          end

          # Track fact recall failures
          if fr < 1.0
            missed_facts = exp_facts.reject { |exp| ext_facts.any? { |e| matches?(e, exp) } }
            missed_preds = missed_facts.map { |m| "#{m["predicate"] || m[:predicate]}:#{m["object"] || m[:object]}" }.join(", ")
            failures << "MISS #{tc["id"]}: expected facts [#{missed_preds}]" unless missed_facts.empty?
          end
        end

        # Compute averages
        avg_ep = entity_precisions.sum / entity_precisions.size
        avg_er = entity_recalls.sum / entity_recalls.size
        entity_f1 = f1_score(avg_ep, avg_er)
        avg_fp = fact_precisions.sum / fact_precisions.size
        avg_fr = fact_recalls.sum / fact_recalls.size
        fact_f1 = f1_score(avg_fp, avg_fr)
        avg_cr = concept_recalls.sum / concept_recalls.size

        # Report
        puts "\n  #{category.capitalize} Extraction (#{category_cases.size} cases):"
        puts "    Entity  - Precision: #{avg_ep.round(3)}  Recall: #{avg_er.round(3)}  F1: #{entity_f1.round(3)}"
        puts "    Fact    - Precision: #{avg_fp.round(3)}  Recall: #{avg_fr.round(3)}  F1: #{fact_f1.round(3)}"
        puts "    Concept Recall: #{avg_cr.round(3)}"

        if failures.any?
          puts "    Failures (#{failures.size}):"
          failures.first(5).each { |f| puts "      #{f}" }
          puts "      ... and #{failures.size - 5} more" if failures.size > 5
        end

        # Soft assertion — report metrics, don't fail on thresholds
        expect(category_cases.size).to be > 0
      end
    end
  end

  describe "aggregate extraction performance" do
    it "reports overall metrics across all cases" do
      entity_precisions = []
      entity_recalls = []
      fact_precisions = []
      fact_recalls = []
      concept_recalls = []

      cases.each do |tc|
        extraction = distiller.distill(tc["text"])
        expected = tc.fetch("expected", {})

        exp_entities = expected.fetch("entities", [])
        ext_entities = extraction.entities.map { |e| {type: e[:type], name: e[:name]} }
        entity_precisions << extraction_precision(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }
        entity_recalls << extraction_recall(ext_entities, exp_entities) { |e, exp| matches?(e, exp) }

        exp_facts = expected.fetch("facts", [])
        ext_facts = extraction.facts.map { |f|
          h = {predicate: f[:predicate], object: f[:object]}
          h[:scope_hint] = f[:scope_hint] if f[:scope_hint]
          h
        }
        fact_precisions << extraction_precision(ext_facts, exp_facts) { |e, exp| matches?(e, exp) }
        fact_recalls << extraction_recall(ext_facts, exp_facts) { |e, exp| matches?(e, exp) }

        concepts = tc.fetch("concepts", [])
        concept_recalls << null_distiller_concept_recall(extraction, concepts)
      end

      avg_ep = entity_precisions.sum / entity_precisions.size
      avg_er = entity_recalls.sum / entity_recalls.size
      avg_fp = fact_precisions.sum / fact_precisions.size
      avg_fr = fact_recalls.sum / fact_recalls.size
      avg_cr = concept_recalls.sum / concept_recalls.size

      puts "\n  AGGREGATE (#{cases.size} cases):"
      puts "    Entity  - Precision: #{avg_ep.round(3)}  Recall: #{avg_er.round(3)}  F1: #{f1_score(avg_ep, avg_er).round(3)}"
      puts "    Fact    - Precision: #{avg_fp.round(3)}  Recall: #{avg_fr.round(3)}  F1: #{f1_score(avg_fp, avg_fr).round(3)}"
      puts "    Concept Recall: #{avg_cr.round(3)}"

      expect(cases.size).to be > 0
    end
  end
end
