# frozen_string_literal: true

module ClaudeMemory
  module Store
    # Ingestion metrics persistence and aggregation for the SQLiteStore.
    # Records per-distillation LLM token usage and extraction counts, and
    # computes totals + efficiency ratios over the full history.
    module MetricsAggregator
      # Count content items that have not yet been distilled.
      # @param min_length [Integer] minimum byte_len threshold
      # @return [Integer]
      def count_undistilled(min_length: 200)
        content_items
          .left_join(:ingestion_metrics, content_item_id: :id)
          .where(Sequel[:ingestion_metrics][:id] => nil)
          .where { byte_len >= min_length }
          .count
      end

      # Record token usage and extraction counts for a distillation run.
      # @param content_item_id [Integer] content item that was distilled
      # @param input_tokens [Integer] LLM input tokens consumed
      # @param output_tokens [Integer] LLM output tokens consumed
      # @param facts_extracted [Integer] number of facts extracted
      # @return [Integer] inserted row id
      def record_ingestion_metrics(content_item_id:, input_tokens:, output_tokens:, facts_extracted:)
        ingestion_metrics.insert(
          content_item_id: content_item_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          facts_extracted: facts_extracted,
          created_at: Time.now.utc.iso8601
        )
      end

      # Compute aggregate ingestion metrics across all distillation runs.
      # @return [Hash, nil] totals and efficiency ratio, or nil if no data
      def aggregate_ingestion_metrics
        # standard:disable Performance/Detect (Sequel DSL requires .select{}.first)
        result = ingestion_metrics
          .select {
            [
              sum(:input_tokens).as(:total_input),
              sum(:output_tokens).as(:total_output),
              sum(:facts_extracted).as(:total_facts),
              count(:id).as(:total_ops)
            ]
          }
          .first
        # standard:enable Performance/Detect

        return nil if result.nil? || result[:total_ops].to_i.zero?

        total_input = result[:total_input].to_i
        total_output = result[:total_output].to_i
        total_facts = result[:total_facts].to_i
        total_ops = result[:total_ops].to_i

        efficiency = total_input.zero? ? 0.0 : (total_facts.to_f / total_input * 1000).round(2)

        {
          total_input_tokens: total_input,
          total_output_tokens: total_output,
          total_facts_extracted: total_facts,
          total_operations: total_ops,
          avg_facts_per_1k_input_tokens: efficiency
        }
      end

      # Mark all undistilled content items as distilled with zero token counts.
      # Used for backfilling legacy content that predates the metrics table.
      # @return [Integer] number of items backfilled
      def backfill_distillation_metrics!
        undistilled_ids = content_items
          .left_join(:ingestion_metrics, content_item_id: :id)
          .where(Sequel[:ingestion_metrics][:id] => nil)
          .select_map(Sequel[:content_items][:id])

        return 0 if undistilled_ids.empty?

        now = Time.now.utc.iso8601
        undistilled_ids.each do |cid|
          ingestion_metrics.insert(
            content_item_id: cid,
            input_tokens: 0,
            output_tokens: 0,
            facts_extracted: 0,
            created_at: now
          )
        end

        undistilled_ids.size
      end
    end
  end
end
