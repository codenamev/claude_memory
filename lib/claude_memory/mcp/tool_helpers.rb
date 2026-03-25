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

      # Extract optional intent parameter for query disambiguation
      # @param args [Hash] Tool arguments
      # @return [String, nil] Intent string or nil if not provided/blank
      def extract_intent(args)
        intent = args["intent"]
        (intent.nil? || intent.to_s.strip.empty?) ? nil : intent.to_s.strip
      end

      # Collect undistilled content items from both stores (or legacy store)
      # @param limit [Integer] Maximum items to return
      # @param min_length [Integer] Minimum byte_len to include
      # @return [Array<Hash>] Undistilled items sorted by recency
      def collect_undistilled_items(limit:, min_length: 200)
        if @manager
          stores = []
          stores << @manager.project_store if @manager.project_exists?
          stores << @manager.global_store if @manager.global_exists?
          items = stores.flat_map { |s| s.undistilled_content_items(limit: limit, min_length: min_length) }
          items.sort_by { |i| i[:occurred_at] || "" }.reverse.first(limit)
        elsif @legacy_store
          @legacy_store.undistilled_content_items(limit: limit, min_length: min_length)
        else
          []
        end
      end

      # Find the store containing a given content item
      # @param content_item_id [Integer] Content item ID to locate
      # @return [Store::SQLiteStore, nil] The store containing the item, or nil
      def find_store_for_content_item(content_item_id)
        if @manager
          if @manager.project_store&.content_items&.where(id: content_item_id)&.any?
            @manager.project_store
          elsif @manager.global_store&.content_items&.where(id: content_item_id)&.any?
            @manager.global_store
          end
        elsif @legacy_store
          if @legacy_store.content_items.where(id: content_item_id).any?
            @legacy_store
          end
        end
      end
    end
  end
end
