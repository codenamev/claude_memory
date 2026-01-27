# frozen_string_literal: true

module ClaudeMemory
  module MCP
    # Shared utility methods for MCP tool implementations
    # Reduces duplication across tool methods
    module ToolHelpers
      # Standard error response when database is not accessible
      # @param error [Exception] The caught database error
      # @return [Hash] Formatted error response with recommendations
      def database_not_found_error(error)
        {
          error: "Database not found or not accessible",
          message: "ClaudeMemory may not be initialized. Run memory.check_setup for detailed status.",
          details: error.message,
          recommendations: [
            "Run memory.check_setup to diagnose the issue",
            "If not initialized, run: claude-memory init",
            "For help: claude-memory doctor"
          ]
        }
      end

      # Format a fact hash for API response
      # @param fact [Hash] Fact record from database
      # @return [Hash] Formatted fact with standard fields
      def format_fact(fact)
        {
          id: fact[:id],
          subject: fact[:subject_name],
          predicate: fact[:predicate],
          object: fact[:object_literal],
          status: fact[:status],
          scope: fact[:scope]
        }
      end

      # Format a receipt hash for API response
      # @param receipt [Hash] Provenance record from database
      # @return [Hash] Formatted receipt with quote and strength
      def format_receipt(receipt)
        {
          quote: receipt[:quote],
          strength: receipt[:strength]
        }
      end

      # Format a result with fact and receipts
      # @param result [Hash] Result hash with :fact and :receipts keys
      # @return [Hash] Formatted result with source
      def format_result(result)
        {
          id: result[:fact][:id],
          subject: result[:fact][:subject_name],
          predicate: result[:fact][:predicate],
          object: result[:fact][:object_literal],
          scope: result[:fact][:scope],
          source: result[:source],
          receipts: result[:receipts].map { |r| format_receipt(r) }
        }
      end

      # Get default scope from arguments
      # @param args [Hash] Tool arguments
      # @param default [String] Default scope if not specified
      # @return [String] Scope value
      def extract_scope(args, default: "all")
        args["scope"] || default
      end

      # Get default limit from arguments
      # @param args [Hash] Tool arguments
      # @param default [Integer] Default limit if not specified
      # @return [Integer] Limit value
      def extract_limit(args, default: 10)
        args["limit"] || default
      end
    end
  end
end
