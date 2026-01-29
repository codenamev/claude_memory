# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Pure logic for formatting domain objects into MCP tool responses
    # Follows Functional Core pattern - no I/O, just transformations
    class ResponseFormatter
      # Format recall query results into MCP response
      # @param results [Array<Hash>] Recall results with :fact and :receipts
      # @return [Hash] MCP response with facts array
      def self.format_recall_results(results)
        {
          facts: results.map { |r| format_recall_fact(r) }
        }
      end

      # Format single recall fact result
      # @param result [Hash] Single result with :fact, :receipts, :source
      # @return [Hash] Formatted fact for MCP response
      def self.format_recall_fact(result)
        {
          id: result[:fact][:id],
          subject: result[:fact][:subject_name],
          predicate: result[:fact][:predicate],
          object: result[:fact][:object_literal],
          status: result[:fact][:status],
          source: result[:source],
          receipts: result[:receipts].map { |p| format_receipt(p) }
        }
      end

      # Format index query results with token estimates
      # @param query [String] Original query
      # @param scope [String] Scope used
      # @param results [Array<Hash>] Index results with fact data
      # @return [Hash] MCP response with metadata and facts
      def self.format_index_results(query, scope, results)
        total_tokens = results.sum { |r| r[:token_estimate] }

        {
          query: query,
          scope: scope,
          result_count: results.size,
          total_estimated_tokens: total_tokens,
          facts: results.map { |r| format_index_fact(r) }
        }
      end

      # Format single index fact with preview
      # @param result [Hash] Index result with fact data and token estimate
      # @return [Hash] Formatted fact for index response
      def self.format_index_fact(result)
        {
          id: result[:id],
          subject: result[:subject],
          predicate: result[:predicate],
          object_preview: result[:object_preview],
          status: result[:status],
          scope: result[:scope],
          confidence: result[:confidence],
          tokens: result[:token_estimate],
          source: result[:source]
        }
      end

      # Format explanation with full fact details and relationships
      # @param explanation [Hash] Explanation with :fact, :receipts, :supersedes, etc.
      # @param scope [String] Source scope
      # @return [Hash] MCP response with fact, receipts, and relationships
      def self.format_explanation(explanation, scope)
        {
          fact: {
            id: explanation[:fact][:id],
            subject: explanation[:fact][:subject_name],
            predicate: explanation[:fact][:predicate],
            object: explanation[:fact][:object_literal],
            status: explanation[:fact][:status],
            valid_from: explanation[:fact][:valid_from],
            valid_to: explanation[:fact][:valid_to]
          },
          source: scope,
          receipts: explanation[:receipts].map { |p| format_receipt(p) },
          supersedes: explanation[:supersedes],
          superseded_by: explanation[:superseded_by],
          conflicts: explanation[:conflicts].map { |c| c[:id] }
        }
      end

      # Format detailed explanation for recall_details response
      # @param explanation [Hash] Explanation with full relationships
      # @return [Hash] Detailed fact response
      def self.format_detailed_explanation(explanation)
        {
          fact: {
            id: explanation[:fact][:id],
            subject: explanation[:fact][:subject_name],
            predicate: explanation[:fact][:predicate],
            object: explanation[:fact][:object_literal],
            status: explanation[:fact][:status],
            confidence: explanation[:fact][:confidence],
            scope: explanation[:fact][:scope],
            valid_from: explanation[:fact][:valid_from],
            valid_to: explanation[:fact][:valid_to]
          },
          receipts: explanation[:receipts].map { |r| format_detailed_receipt(r) },
          relationships: {
            supersedes: explanation[:supersedes],
            superseded_by: explanation[:superseded_by],
            conflicts: explanation[:conflicts].map { |c| {id: c[:id], status: c[:status]} }
          }
        }
      end

      # Format receipt (provenance) with minimal fields
      # @param receipt [Hash] Receipt with :quote and :strength
      # @return [Hash] Formatted receipt
      def self.format_receipt(receipt)
        {quote: receipt[:quote], strength: receipt[:strength]}
      end

      # Format detailed receipt with session and timestamp
      # @param receipt [Hash] Receipt with full fields
      # @return [Hash] Formatted detailed receipt
      def self.format_detailed_receipt(receipt)
        {
          quote: receipt[:quote],
          strength: receipt[:strength],
          session_id: receipt[:session_id],
          occurred_at: receipt[:occurred_at]
        }
      end

      # Format changes list into MCP response
      # @param since [String] ISO timestamp
      # @param changes [Array<Hash>] Change records
      # @return [Hash] MCP response with since and formatted changes
      def self.format_changes(since, changes)
        {
          since: since,
          changes: changes.map { |c| format_change(c) }
        }
      end

      # Format single change record
      # @param change [Hash] Change with fact fields
      # @return [Hash] Formatted change
      def self.format_change(change)
        {
          id: change[:id],
          predicate: change[:predicate],
          object: change[:object_literal],
          status: change[:status],
          created_at: change[:created_at],
          source: change[:source]
        }
      end

      # Format conflicts list into MCP response
      # @param conflicts [Array<Hash>] Conflict records
      # @return [Hash] MCP response with count and formatted conflicts
      def self.format_conflicts(conflicts)
        {
          count: conflicts.size,
          conflicts: conflicts.map { |c| format_conflict(c) }
        }
      end

      # Format single conflict record
      # @param conflict [Hash] Conflict with fact IDs
      # @return [Hash] Formatted conflict
      def self.format_conflict(conflict)
        {
          id: conflict[:id],
          fact_a: conflict[:fact_a_id],
          fact_b: conflict[:fact_b_id],
          status: conflict[:status],
          source: conflict[:source]
        }
      end

      # Format sweep statistics into MCP response
      # @param scope [String] Database scope swept
      # @param stats [Hash] Sweeper stats
      # @return [Hash] Formatted sweep response
      def self.format_sweep_stats(scope, stats)
        {
          scope: scope,
          proposed_expired: stats[:proposed_facts_expired],
          disputed_expired: stats[:disputed_facts_expired],
          orphaned_deleted: stats[:orphaned_provenance_deleted],
          content_pruned: stats[:old_content_pruned],
          elapsed_seconds: stats[:elapsed_seconds].round(3)
        }
      end

      # Format semantic search results with similarity scores
      # @param query [String] Search query
      # @param mode [String] Search mode (vector, text, both)
      # @param scope [String] Scope
      # @param results [Array<Hash>] Results with similarity scores
      # @return [Hash] Formatted semantic search response
      def self.format_semantic_results(query, mode, scope, results)
        {
          query: query,
          mode: mode,
          scope: scope,
          count: results.size,
          facts: results.map { |r| format_semantic_fact(r) }
        }
      end

      # Format single semantic search fact with similarity
      # @param result [Hash] Result with fact, receipts, and similarity
      # @return [Hash] Formatted fact with similarity
      def self.format_semantic_fact(result)
        {
          id: result[:fact][:id],
          subject: result[:fact][:subject_name],
          predicate: result[:fact][:predicate],
          object: result[:fact][:object_literal],
          scope: result[:fact][:scope],
          source: result[:source],
          similarity: result[:similarity],
          receipts: result[:receipts].map { |r| format_receipt(r) }
        }
      end

      # Format concept search results
      # @param concepts [Array<String>] Concepts searched
      # @param scope [String] Scope
      # @param results [Array<Hash>] Results with similarity scores
      # @return [Hash] Formatted concept search response
      def self.format_concept_results(concepts, scope, results)
        {
          concepts: concepts,
          scope: scope,
          count: results.size,
          facts: results.map { |r| format_concept_fact(r) }
        }
      end

      # Format single concept search fact with multi-concept similarity
      # @param result [Hash] Result with average and per-concept similarities
      # @return [Hash] Formatted fact with concept similarities
      def self.format_concept_fact(result)
        {
          id: result[:fact][:id],
          subject: result[:fact][:subject_name],
          predicate: result[:fact][:predicate],
          object: result[:fact][:object_literal],
          scope: result[:fact][:scope],
          source: result[:source],
          average_similarity: result[:similarity],
          concept_similarities: result[:concept_similarities],
          receipts: result[:receipts].map { |r| format_receipt(r) }
        }
      end

      # Format shortcut query results (decisions, architecture, etc.)
      # @param category [String] Shortcut category name
      # @param results [Array<Hash>] Query results
      # @return [Hash] Formatted shortcut response
      def self.format_shortcut_results(category, results)
        {
          category: category,
          count: results.size,
          facts: results.map { |r| format_shortcut_fact(r) }
        }
      end

      # Format fact for shortcut queries (includes scope, no status)
      # @param result [Hash] Result with fact data
      # @return [Hash] Formatted fact
      def self.format_shortcut_fact(result)
        {
          id: result[:fact][:id],
          subject: result[:fact][:subject_name],
          predicate: result[:fact][:predicate],
          object: result[:fact][:object_literal],
          scope: result[:fact][:scope],
          source: result[:source]
        }
      end
    end
  end
end
