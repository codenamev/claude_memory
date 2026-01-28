# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Pure business logic for ranking, sorting, and deduplicating facts
    # Follows Functional Core pattern (Gary Bernhardt) - no I/O, just transformations
    class FactRanker
      # Deduplicate index results by fact signature and sort by source priority
      # @param results [Array<Hash>] Results with :subject, :predicate, :object_preview, :source
      # @param limit [Integer] Maximum results to return
      # @return [Array<Hash>] Deduplicated and sorted results
      def self.dedupe_and_sort_index(results, limit)
        seen_signatures = Set.new
        unique_results = []

        results.each do |result|
          sig = "#{result[:subject]}:#{result[:predicate]}:#{result[:object_preview]}"
          next if seen_signatures.include?(sig)

          seen_signatures.add(sig)
          unique_results << result
        end

        # Sort by source priority (project first)
        unique_results.sort_by do |item|
          source_priority = (item[:source] == :project) ? 0 : 1
          [source_priority]
        end.first(limit)
      end

      # Deduplicate full fact results by signature and sort by source + creation time
      # @param results [Array<Hash>] Results with :fact hash containing fact data, :source symbol
      # @param limit [Integer] Maximum results to return
      # @return [Array<Hash>] Deduplicated and sorted results
      def self.dedupe_and_sort(results, limit)
        seen_signatures = Set.new
        unique_results = []

        results.each do |result|
          fact = result[:fact]
          sig = "#{fact[:subject_name]}:#{fact[:predicate]}:#{fact[:object_literal]}"
          next if seen_signatures.include?(sig)

          seen_signatures.add(sig)
          unique_results << result
        end

        unique_results.sort_by do |item|
          source_priority = (item[:source] == :project) ? 0 : 1
          [source_priority, item[:fact][:created_at]]
        end.first(limit)
      end

      # Sort facts by scope priority: current project > global > other projects
      # @param facts_with_provenance [Array<Hash>] Facts with :fact hash containing scope and project_path
      # @param project_path [String] Current project path for comparison
      # @return [Array<Hash>] Sorted facts
      def self.sort_by_scope_priority(facts_with_provenance, project_path)
        facts_with_provenance.sort_by do |item|
          fact = item[:fact]
          is_current_project = fact[:project_path] == project_path
          is_global = fact[:scope] == "global"

          [is_current_project ? 0 : 1, is_global ? 0 : 1]
        end
      end

      # Deduplicate semantic search results by fact_id, keeping highest similarity
      # @param results [Array<Hash>] Results with :fact hash containing :id and :similarity score
      # @param limit [Integer] Maximum results to return
      # @return [Array<Hash>] Deduplicated results sorted by similarity descending
      def self.dedupe_by_fact_id(results, limit)
        seen = {}

        results.each do |result|
          fact_id = result[:fact][:id]
          # Keep the result with highest similarity for each fact
          if !seen[fact_id] || seen[fact_id][:similarity] < result[:similarity]
            seen[fact_id] = result
          end
        end

        seen.values.sort_by { |r| -r[:similarity] }.take(limit)
      end

      # Merge vector and text search results, preferring vector similarity scores
      # @param vector_results [Array<Hash>] Results from vector search with :fact and :similarity
      # @param text_results [Array<Hash>] Results from text search with :fact and :similarity
      # @param limit [Integer] Maximum results to return
      # @return [Array<Hash>] Merged results sorted by similarity descending
      def self.merge_search_results(vector_results, text_results, limit)
        # Combine results, preferring vector similarity scores
        combined = {}

        vector_results.each do |result|
          fact_id = result[:fact][:id]
          combined[fact_id] = result
        end

        text_results.each do |result|
          fact_id = result[:fact][:id]
          # Only add if not already present from vector search
          combined[fact_id] ||= result
        end

        # Sort by similarity score (highest first)
        combined.values
          .sort_by { |r| -(r[:similarity] || 0) }
          .take(limit)
      end
    end
  end
end
