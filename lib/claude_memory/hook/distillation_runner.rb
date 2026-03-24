# frozen_string_literal: true

module ClaudeMemory
  module Hook
    class DistillationRunner
      MIN_TEXT_LENGTH = 200

      def initialize(store, distiller: Distill::NullDistiller.new)
        @store = store
        @distiller = distiller
      end

      def distill_item(content_id, project_path:, scope: "project")
        item = @store.get_content_item(content_id)
        return unless item

        raw_text = item[:raw_text]
        return unless raw_text && raw_text.length >= MIN_TEXT_LENGTH

        extraction = @distiller.distill(raw_text, content_item_id: content_id)
        return if extraction.empty?

        resolver = Resolve::Resolver.new(@store)
        @store.db.transaction do
          resolve_result = resolver.apply(
            extraction, content_item_id: content_id,
            project_path: project_path, scope: scope
          )
          @store.record_ingestion_metrics(
            content_item_id: content_id, input_tokens: 0,
            output_tokens: 0, facts_extracted: resolve_result[:facts_created]
          )
        end
      rescue => e
        ClaudeMemory.logger.warn("DistillationRunner#distill_item(#{content_id}) failed: #{e.class} - #{e.message}")
        ClaudeMemory.logger.warn(e.backtrace.first(5).join("\n"))
      end

      def distill_batch(project_path:, limit: 5)
        items = @store.undistilled_content_items(limit: limit, min_length: MIN_TEXT_LENGTH)
        items.each { |item| distill_item(item[:id], project_path: project_path) }
        items.size
      end
    end
  end
end
