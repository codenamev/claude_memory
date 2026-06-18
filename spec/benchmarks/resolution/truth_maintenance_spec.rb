# frozen_string_literal: true

require_relative "../benchmark_helper"

module BenchmarkHelpers
  Extraction = Struct.new(:entities, :facts)
end

RSpec.describe "Truth Maintenance", :benchmark do
  include BenchmarkHelpers::BenchmarkSetup

  let(:resolution_cases) { BenchmarkHelpers::DatasetLoader.load_resolution_cases }

  describe "resolution correctness by outcome type" do
    %w[supersede conflict accumulate corroborate].each do |outcome_type|
      context "#{outcome_type} cases" do
        let(:cases_for_type) do
          resolution_cases.select { |c| c["expected_outcome"] == outcome_type }
        end

        it "correctly resolves #{outcome_type} scenarios" do
          skip "No #{outcome_type} cases" if cases_for_type.empty?

          correct = 0
          total = cases_for_type.size
          failures = []

          cases_for_type.each do |test_case|
            tmpdir = Dir.mktmpdir("resolution_#{test_case["id"]}")
            test_db_path = File.join(tmpdir, ".claude/memory.sqlite3")
            FileUtils.mkdir_p(File.dirname(test_db_path))

            begin
              store = ClaudeMemory::Store::SQLiteStore.new(test_db_path)
              resolver = ClaudeMemory::Resolve::Resolver.new(store)

              existing = test_case["existing_fact"]
              incoming = test_case["incoming_fact"]

              # Step 1: Insert the existing fact via resolver
              existing_extraction = BenchmarkHelpers::Extraction.new(
                entities: [{type: "repo", name: existing["subject"] || "repo"}],
                facts: [{
                  subject: existing["subject"] || "repo",
                  predicate: existing["predicate"],
                  object: existing["object"],
                  strength: existing["strength"] || "stated",
                  quote: existing["object"]
                }]
              )

              existing_content_id = store.upsert_content_item(
                source: "test",
                session_id: "test-existing",
                text_hash: Digest::SHA256.hexdigest("existing-#{test_case["id"]}"),
                byte_len: 100,
                raw_text: "Existing fact: #{existing["object"]}"
              )

              resolver.apply(
                existing_extraction,
                content_item_id: existing_content_id,
                occurred_at: "2024-01-01T00:00:00Z"
              )

              # Step 2: Apply the incoming fact via resolver
              incoming_extraction = BenchmarkHelpers::Extraction.new(
                entities: [{type: "repo", name: incoming["subject"] || "repo"}],
                facts: [{
                  subject: incoming["subject"] || "repo",
                  predicate: incoming["predicate"],
                  object: incoming["object"],
                  strength: incoming["strength"] || "stated",
                  supersedes: incoming["supersedes"] || false,
                  quote: incoming["object"]
                }]
              )

              incoming_content_id = store.upsert_content_item(
                source: "test",
                session_id: "test-incoming",
                text_hash: Digest::SHA256.hexdigest("incoming-#{test_case["id"]}"),
                byte_len: 100,
                raw_text: "Incoming fact: #{incoming["object"]}"
              )

              result = resolver.apply(
                incoming_extraction,
                content_item_id: incoming_content_id,
                occurred_at: "2024-06-01T00:00:00Z"
              )

              # Step 3: Determine actual outcome
              actual_outcome = determine_outcome(result)

              if actual_outcome == outcome_type
                correct += 1
              else
                failures << {
                  id: test_case["id"],
                  expected: outcome_type,
                  actual: actual_outcome,
                  rationale: test_case["rationale"]
                }
              end

              store.close
            ensure
              FileUtils.rm_rf(tmpdir)
            end
          end

          accuracy = total.zero? ? 0.0 : correct.to_f / total
          puts "  #{outcome_type}: #{correct}/#{total} (#{(accuracy * 100).round(1)}%)"

          if failures.any?
            failures.first(3).each do |f|
              puts "    FAIL #{f[:id]}: expected=#{f[:expected]} actual=#{f[:actual]}"
            end
          end

          expect(accuracy).to be >= 0.8,
            "#{outcome_type} accuracy should be at least 80%, got #{(accuracy * 100).round(1)}% " \
            "(#{failures.size} failures: #{failures.map { |f| f[:id] }.join(", ")})"
        end
      end
    end
  end

  describe "aggregate resolution accuracy" do
    it "reports overall confusion matrix" do
      outcomes = Hash.new { |h, k| h[k] = Hash.new(0) }
      total = 0
      correct = 0

      resolution_cases.each do |test_case|
        tmpdir = Dir.mktmpdir("resolution_agg_#{test_case["id"]}")
        test_db_path = File.join(tmpdir, ".claude/memory.sqlite3")
        FileUtils.mkdir_p(File.dirname(test_db_path))

        begin
          store = ClaudeMemory::Store::SQLiteStore.new(test_db_path)
          resolver = ClaudeMemory::Resolve::Resolver.new(store)

          existing = test_case["existing_fact"]
          incoming = test_case["incoming_fact"]

          existing_extraction = BenchmarkHelpers::Extraction.new(
            entities: [{type: "repo", name: existing["subject"] || "repo"}],
            facts: [{
              subject: existing["subject"] || "repo",
              predicate: existing["predicate"],
              object: existing["object"],
              strength: existing["strength"] || "stated",
              quote: existing["object"]
            }]
          )

          existing_content_id = store.upsert_content_item(
            source: "test",
            session_id: "test-existing",
            text_hash: Digest::SHA256.hexdigest("existing-agg-#{test_case["id"]}"),
            byte_len: 100,
            raw_text: "Existing: #{existing["object"]}"
          )

          resolver.apply(
            existing_extraction,
            content_item_id: existing_content_id,
            occurred_at: "2024-01-01T00:00:00Z"
          )

          incoming_extraction = BenchmarkHelpers::Extraction.new(
            entities: [{type: "repo", name: incoming["subject"] || "repo"}],
            facts: [{
              subject: incoming["subject"] || "repo",
              predicate: incoming["predicate"],
              object: incoming["object"],
              strength: incoming["strength"] || "stated",
              supersedes: incoming["supersedes"] || false,
              quote: incoming["object"]
            }]
          )

          incoming_content_id = store.upsert_content_item(
            source: "test",
            session_id: "test-incoming",
            text_hash: Digest::SHA256.hexdigest("incoming-agg-#{test_case["id"]}"),
            byte_len: 100,
            raw_text: "Incoming: #{incoming["object"]}"
          )

          result = resolver.apply(
            incoming_extraction,
            content_item_id: incoming_content_id,
            occurred_at: "2024-06-01T00:00:00Z"
          )

          expected = test_case["expected_outcome"]
          actual = determine_outcome(result)

          outcomes[expected][actual] += 1
          total += 1
          correct += 1 if actual == expected

          store.close
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      end

      accuracy = total.zero? ? 0.0 : correct.to_f / total

      puts "\n  Resolution Confusion Matrix:"
      puts "  " + "=" * 50
      puts "  Expected \\ Actual  | supersede | conflict | accumulate | corroborate"
      puts "  " + "-" * 50
      %w[supersede conflict accumulate corroborate].each do |expected|
        row = %w[supersede conflict accumulate corroborate].map { |actual|
          outcomes[expected][actual].to_s.rjust(9)
        }.join(" | ")
        puts "  #{expected.ljust(18)} | #{row}"
      end
      puts "  " + "=" * 50
      puts "  Overall Accuracy: #{correct}/#{total} (#{(accuracy * 100).round(1)}%)"

      expect(accuracy).to be >= 0.85,
        "Overall resolution accuracy should be at least 85%, got #{(accuracy * 100).round(1)}%"
    end
  end

  private

  def determine_outcome(result)
    if result[:provenance_created] > 0 && result[:facts_created] == 0 && result[:facts_superseded] == 0
      "corroborate"
    elsif result[:facts_superseded] > 0
      "supersede"
    elsif result[:conflicts_created] > 0
      "conflict"
    elsif result[:facts_created] > 0 && result[:facts_superseded] == 0 && result[:conflicts_created] == 0
      "accumulate"
    else
      "unknown"
    end
  end
end
