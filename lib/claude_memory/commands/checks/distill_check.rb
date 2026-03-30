# frozen_string_literal: true

module ClaudeMemory
  module Commands
    module Checks
      # Checks for content items missing distillation metrics
      class DistillCheck
        def initialize(db_path, label)
          @db_path = db_path
          @label = label
        end

        def call
          unless File.exist?(@db_path)
            return {
              status: :ok,
              label: "#{@label}_distill",
              message: "#{@label.capitalize} database not found (skipping distill check)",
              details: {}
            }
          end

          check_undistilled_content
        rescue => e
          {
            status: :error,
            label: "#{@label}_distill",
            message: "#{@label.capitalize} distill check error: #{e.message}",
            details: {}
          }
        end

        private

        def check_undistilled_content
          store = ClaudeMemory::Store::SQLiteStore.new(@db_path)

          undistilled_count = store.content_items
            .left_join(:ingestion_metrics, content_item_id: :id)
            .where(Sequel[:ingestion_metrics][:id] => nil)
            .count

          store.close

          warnings = []
          if undistilled_count > 0
            warnings << "#{undistilled_count} content items have no distillation metrics. Run 'claude-memory init' to migrate."
          end

          {
            status: warnings.any? ? :warning : :ok,
            label: "#{@label}_distill",
            message: "#{@label.capitalize} distillation metrics: #{(undistilled_count == 0) ? "all tracked" : "#{undistilled_count} untracked"}",
            details: {undistilled_count: undistilled_count},
            warnings: warnings
          }
        end
      end
    end
  end
end
