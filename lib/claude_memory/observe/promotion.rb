# frozen_string_literal: true

module ClaudeMemory
  module Observe
    # Server-side corroboration gate + Resolver path for promoting an
    # observation to a structured fact. Shared by the CLI
    # (`claude-memory observations promote`) and the `memory.promote_observation`
    # MCP tool so the anti-hallucination threshold and fact-creation path are
    # enforced identically across both surfaces.
    class Promotion
      # Outcome of a promotion attempt. `error` is set on refusal; the fact
      # fields are set on success. `success?` distinguishes the two.
      Result = Struct.new(:fact_id, :predicate, :object, :corroboration_count, :facts_created, :error) do
        def success?
          error.nil?
        end
      end

      def initialize(store, scope: "project")
        @store = store
        @scope = scope
      end

      # @return [Result]
      def call(observation_id:, predicate:, object:, subject: "repo")
        return failure("predicate and object are required") if predicate.nil? || object.to_s.strip.empty?

        obs = @store.observations.where(id: observation_id).first
        return failure("Observation #{observation_id} not found in #{@scope} database") unless obs
        return failure("Observation #{observation_id} already promoted (fact ##{obs[:promoted_fact_id]})") unless obs[:promoted_at].nil?

        threshold = Domain::Observation::PROMOTION_THRESHOLD
        if obs[:corroboration_count].to_i < threshold
          return failure("Not yet corroborated: observation #{observation_id} has #{obs[:corroboration_count]} sighting(s), " \
            "need #{threshold}. Promotion requires repeated corroboration (anti-hallucination gate).")
        end

        fact_id, facts_created = create_fact(obs, subject, predicate, object)
        unless fact_id
          return failure("Promotion failed: the fact for observation #{observation_id} could not be resolved after creation")
        end

        @store.mark_observation_promoted(observation_id, fact_id: fact_id)

        Result.new(
          fact_id, Resolve::PredicatePolicy.canonicalize(predicate), object,
          obs[:corroboration_count], facts_created, nil
        )
      end

      private

      def create_fact(obs, subject, predicate, object)
        project_path = (@scope == "global") ? nil : Configuration.new.project_dir
        extraction = Distill::Extraction.new(
          facts: [{subject: subject, predicate: predicate, object: object, strength: "derived"}]
        )
        result = Resolve::Resolver.new(@store).apply(
          extraction, content_item_id: obs[:source_content_item_id],
          occurred_at: Time.now.utc.iso8601, project_path: project_path, scope: @scope
        )
        # The resolver reports the id of the fact it actually touched (inserted,
        # reinforced, or disputed) — no need to re-query for it.
        [result[:fact_ids].compact.first, result[:facts_created]]
      end

      def failure(message)
        Result.new(nil, nil, nil, nil, nil, message)
      end
    end
  end
end
