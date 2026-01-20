# frozen_string_literal: true

module ClaudeMemory
  module Distill
    class NullDistiller < Distiller
      DECISION_PATTERNS = [
        /\b(?:we\s+)?decided\s+to\s+(.+)/i,
        /\b(?:we\s+)?agreed\s+(?:to\s+|on\s+)(.+)/i,
        /\blet'?s\s+(?:go\s+with|use)\s+(.+)/i,
        /\bgoing\s+(?:forward|ahead)\s+with\s+(.+)/i
      ].freeze

      CONVENTION_PATTERNS = [
        /\balways\s+(.+)/i,
        /\bnever\s+(.+)/i,
        /\bconvention[:\s]+(.+)/i,
        /\bstandard[:\s]+(.+)/i,
        /\bwe\s+use\s+(.+)/i
      ].freeze

      ENTITY_PATTERNS = {
        "database" => /\b(postgresql|postgres|mysql|sqlite|mongodb|redis)\b/i,
        "framework" => /\b(rails|sinatra|django|express|next\.?js|react|vue)\b/i,
        "language" => /\b(ruby|python|javascript|typescript|go|rust)\b/i,
        "platform" => /\b(aws|gcp|azure|heroku|vercel|netlify|docker|kubernetes)\b/i
      }.freeze

      def distill(text, content_item_id: nil)
        entities = extract_entities(text)
        facts = extract_facts(text, entities)
        decisions = extract_decisions(text)
        signals = extract_signals(text)

        Extraction.new(
          entities: entities,
          facts: facts,
          decisions: decisions,
          signals: signals
        )
      end

      private

      def extract_entities(text)
        found = []
        ENTITY_PATTERNS.each do |type, pattern|
          text.scan(pattern).flatten.uniq.each do |name|
            found << {type: type, name: name.downcase, confidence: 0.7}
          end
        end
        found.uniq { |e| [e[:type], e[:name]] }
      end

      def extract_facts(text, entities)
        facts = []

        entities.each do |entity|
          case entity[:type]
          when "database"
            facts << build_fact("uses_database", entity[:name], text)
          when "framework"
            facts << build_fact("uses_framework", entity[:name], text)
          when "platform"
            facts << build_fact("deployment_platform", entity[:name], text)
          end
        end

        facts
      end

      def extract_decisions(text)
        decisions = []
        DECISION_PATTERNS.each do |pattern|
          text.scan(pattern).flatten.each do |match|
            decisions << {
              title: match.strip.slice(0, 100),
              summary: match.strip,
              status_hint: "accepted"
            }
          end
        end
        decisions.first(5)
      end

      def extract_signals(text)
        signals = []
        signals << {kind: "supersession", value: true} if text.match?(/\b(no longer|stopped using|switched from|replaced|deprecated)\b/i)
        signals << {kind: "conflict", value: true} if text.match?(/\b(disagree|conflict|contradiction|but.*said|however.*different)\b/i)
        signals
      end

      def build_fact(predicate, object, text)
        quote = text.slice(0, 200)
        {
          subject: "repo",
          predicate: predicate,
          object: object,
          polarity: "positive",
          confidence: 0.7,
          quote: quote,
          strength: "inferred"
        }
      end
    end
  end
end
