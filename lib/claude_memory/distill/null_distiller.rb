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

      GLOBAL_SCOPE_PATTERNS = [
        /\bi\s+always\b/i,
        /\bin\s+all\s+(?:my\s+)?projects\b/i,
        /\beverywhere\b/i,
        /\bacross\s+all\s+(?:my\s+)?(?:projects|repos|codebases)\b/i,
        /\bmy\s+(?:personal\s+)?(?:preference|convention|standard)\b/i,
        /\bglobally\b/i,
        /\buniversally\b/i
      ].freeze

      # Observation-specific convention patterns: stricter than the shared
      # CONVENTION_PATTERNS. Bare `always (.+)` / `never (.+)` / `we use (.+)`
      # match code, prose, and instruction text ("never answer from memory",
      # "never nil. def …"), so observations require explicit convention
      # framing or a first-person "we always/never".
      OBSERVATION_CONVENTION_PATTERNS = [
        /\bconvention[:\s]+(.+)/i,
        /\bstandard[:\s]+(.+)/i,
        /\bwe\s+(?:should\s+)?(?:always|never)\s+(.+)/i
      ].freeze

      # Bodies that look like code / JSON / shell rather than a statement.
      NOISE_BODY_SIGNATURE = /\bdef\s|\bclass\s|\bmodule\s|=>|::|","|":\s*"|[{}]|\$\(|&&|\|\|/

      def distill(text, content_item_id: nil)
        entities = extract_entities(text)
        facts = extract_facts(text, entities)
        decisions = extract_decisions(text)
        signals = extract_signals(text)
        observations = extract_observations(text)

        Extraction.new(
          entities: entities,
          facts: facts,
          decisions: decisions,
          signals: signals,
          observations: observations
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
        scope_hint = global_scope_signal?(text) ? "global" : "project"

        entities.each do |entity|
          case entity[:type]
          when "database"
            facts << build_fact("uses_database", entity[:name], text, scope_hint)
          when "framework"
            facts << build_fact("uses_framework", entity[:name], text, scope_hint)
          when "platform"
            facts << build_fact("deployment_platform", entity[:name], text, scope_hint)
          when "language"
            facts << build_fact("uses_language", entity[:name], text, scope_hint)
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
        signals << {kind: "global_scope", value: true} if global_scope_signal?(text)
        signals
      end

      # Layer-1 Observer: emit episodic observations for the same signals the
      # distiller can detect by regex. A decision being made and a convention
      # being stated are both "things that happened" worth logging in the
      # episodic layer, independent of the semantic facts they also produce.
      # Decisions are 🔴 (important), conventions 🟡 (maybe) — the priority is
      # an internal Observer/Reflector signal. Richer observations come from
      # the Layer-2 Claude-as-observer pass (a later phase).
      def extract_observations(text)
        observations = []

        DECISION_PATTERNS.each do |pattern|
          text.scan(pattern).flatten.each do |match|
            observations << build_observation("decision", Domain::Observation::IMPORTANT, "decided to #{match.strip}", text)
          end
        end

        OBSERVATION_CONVENTION_PATTERNS.each do |pattern|
          text.scan(pattern).flatten.each do |match|
            observations << build_observation("preference", Domain::Observation::MAYBE, match.strip, text)
          end
        end

        observations.compact.uniq { |o| [o[:kind], o[:body]] }.first(10)
      end

      # Returns nil for content that isn't a usable statement: code/JSON noise,
      # or fewer than three words after trimming to the first sentence.
      def build_observation(kind, priority, body, text)
        cleaned = trim_to_statement(clean_observation_body(body))
        return nil if cleaned.empty? || noise_body?(cleaned) || cleaned.split.size < 3

        {
          kind: kind,
          priority: priority,
          body: cleaned.slice(0, 500),
          scope_hint: global_scope_signal?(text) ? "global" : "project"
        }
      end

      # Cap a captured span to its first sentence (and a hard length limit) so a
      # greedy `.+` match can't swallow a whole code block or JSON line.
      def trim_to_statement(text)
        s = text.to_s.strip
        (s[/\A.{0,240}?[.!?](?=\s|\z)/m] || s[0, 240]).to_s.strip
      end

      def noise_body?(body)
        body.match?(NOISE_BODY_SIGNATURE)
      end

      # The distiller scans raw transcript text, which is JSONL — so a captured
      # body can carry JSON/escaping artifacts (`\n`, `\"`, a trailing `"}`,
      # a leading `= `/`### ` from injected memory/markdown). Normalize them out:
      # cleaner bodies read better in the injected log AND normalize more
      # consistently, which is what the Reflector's dedup/corroboration keys off.
      def clean_observation_body(body)
        body.to_s
          .gsub(/\\+[ntr]/, " ")   # literal \n \t \r (even multiply-escaped) -> space
          .gsub(/\\+"/, '"')       # escaped quote -> quote
          .gsub(/\\+/, "")         # residual backslashes
          .gsub(/\s+/, " ")        # collapse whitespace
          .sub(/\A[\s"'`,:=#*>\-\]}]+/, "")  # leading JSON/markdown artifacts
          .sub(/[\s"'`,:\-\]}]+\z/, "")       # trailing JSON artifacts
          .strip
      end

      def global_scope_signal?(text)
        GLOBAL_SCOPE_PATTERNS.any? { |pattern| text.match?(pattern) }
      end

      def build_fact(predicate, object, text, scope_hint = "project")
        quote = text.slice(0, 200)
        {
          subject: "repo",
          predicate: predicate,
          object: object,
          polarity: "positive",
          confidence: 0.7,
          quote: quote,
          strength: "inferred",
          scope_hint: scope_hint
        }
      end
    end
  end
end
