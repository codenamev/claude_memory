# frozen_string_literal: true

module ComparativeHelpers
  module Adapters
    # Baseline: renders all facts as a CLAUDE.md file for static context injection.
    # Not a retrieval system — always returns [] for search().
    # Tests whether dynamic retrieval outperforms having everything in context.
    class ClaudeMdAdapter < BaseAdapter
      PREDICATE_LABELS = {
        "uses_database" => "Databases",
        "uses_framework" => "Frameworks & Tools",
        "convention" => "Conventions",
        "decision" => "Decisions",
        "auth_method" => "Authentication",
        "deployment_platform" => "Deployment"
      }.freeze

      def initialize
        @facts = []
      end

      def available?
        true
      end

      def name
        "CLAUDE.md baseline"
      end

      def setup(facts, dir)
        @facts = facts.select { |f| f["status"] != "superseded" }
      end

      def search(query, limit: 10)
        # Not a retrieval system
        []
      end

      def last_metrics
        {latency_ms: 0.0, disk_bytes: 0}
      end

      def teardown
        @facts = []
      end

      def supports_e2e?
        true
      end

      def setup_for_claude(dir)
        claude_md_path = File.join(dir, "CLAUDE.md")
        File.write(claude_md_path, render_markdown)
      end

      private

      def render_markdown
        lines = ["# Project Memory", ""]

        # Group active facts by predicate
        grouped = @facts.group_by { |f| f["predicate"] }

        grouped.each do |predicate, facts|
          label = PREDICATE_LABELS.fetch(predicate, predicate.tr("_", " ").capitalize)
          lines << "## #{label}"
          lines << ""

          # Group by subject for clarity
          by_subject = facts.group_by { |f| f["subject"] }
          by_subject.each do |subject, subject_facts|
            lines << "### #{subject}" if by_subject.size > 1
            subject_facts.each do |fact|
              lines << "- #{fact["object"]}"
            end
          end
          lines << ""
        end

        lines.join("\n")
      end
    end
  end
end
