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
    end
  end
end
