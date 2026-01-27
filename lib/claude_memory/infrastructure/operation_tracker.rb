# frozen_string_literal: true

module ClaudeMemory
  module Infrastructure
    # Tracks long-running operations with checkpoints for resumability
    # Enables detection of stuck operations and provides recovery mechanisms
    class OperationTracker
      STALE_THRESHOLD_SECONDS = 86400 # 24 hours

      def initialize(store)
        @store = store
      end

      # Start tracking a new operation
      # Returns operation_id
      def start_operation(operation_type:, scope:, total_items: nil, checkpoint_data: {})
        now = Time.now.utc.iso8601

        # Mark any stale operations as failed before starting new one
        cleanup_stale_operations!(operation_type, scope)

        @store.db[:operation_progress].insert(
          operation_type: operation_type,
          scope: scope,
          status: "running",
          total_items: total_items,
          processed_items: 0,
          checkpoint_data: checkpoint_data.to_json,
          started_at: now,
          completed_at: nil
        )
      end

      # Update progress with new checkpoint data
      def update_progress(operation_id, processed_items:, checkpoint_data: nil)
        updates = {processed_items: processed_items}
        updates[:checkpoint_data] = checkpoint_data.to_json if checkpoint_data
        @store.db[:operation_progress].where(id: operation_id).update(updates)
      end

      # Mark operation as completed
      def complete_operation(operation_id)
        now = Time.now.utc.iso8601
        @store.db[:operation_progress].where(id: operation_id).update(
          status: "completed",
          completed_at: now
        )
      end

      # Mark operation as failed with error message
      def fail_operation(operation_id, error_message)
        now = Time.now.utc.iso8601
        checkpoint_data = @store.db[:operation_progress].where(id: operation_id).get(:checkpoint_data)
        checkpoint = checkpoint_data ? JSON.parse(checkpoint_data) : {}
        checkpoint[:error] = error_message

        @store.db[:operation_progress].where(id: operation_id).update(
          status: "failed",
          completed_at: now,
          checkpoint_data: checkpoint.to_json
        )
      end

      # Get checkpoint data for resuming operation
      # Returns {operation_id:, checkpoint_data:, processed_items:} or nil
      # Only returns non-stale operations (< 24h old)
      def get_checkpoint(operation_type:, scope:)
        threshold_time = (Time.now.utc - STALE_THRESHOLD_SECONDS).iso8601

        op = @store.db[:operation_progress]
          .where(operation_type: operation_type, scope: scope, status: "running")
          .where { started_at >= threshold_time }  # Exclude stale operations
          .order(Sequel.desc(:started_at))
          .first

        return nil unless op

        checkpoint_data = op[:checkpoint_data] ? JSON.parse(op[:checkpoint_data], symbolize_names: true) : {}
        {
          operation_id: op[:id],
          checkpoint_data: checkpoint_data,
          processed_items: op[:processed_items] || 0,
          total_items: op[:total_items],
          started_at: op[:started_at]
        }
      end

      # Get all stuck operations (running for > 24h)
      def stuck_operations
        threshold_time = (Time.now.utc - STALE_THRESHOLD_SECONDS).iso8601

        @store.db[:operation_progress]
          .where(status: "running")
          .where { started_at < threshold_time }
          .all
      end

      # Reset stuck operations to failed status
      def reset_stuck_operations(operation_type: nil, scope: nil)
        dataset = @store.db[:operation_progress].where(status: "running")
        dataset = dataset.where(operation_type: operation_type) if operation_type
        dataset = dataset.where(scope: scope) if scope

        threshold_time = (Time.now.utc - STALE_THRESHOLD_SECONDS).iso8601
        stuck = dataset.where { started_at < threshold_time }

        count = stuck.count
        return 0 if count.zero?

        now = Time.now.utc.iso8601
        error_message = "Reset by recover command - operation exceeded 24h timeout"

        # Fetch each stuck operation, update checkpoint in Ruby, then save
        stuck.all.each do |op|
          checkpoint = op[:checkpoint_data] ? JSON.parse(op[:checkpoint_data]) : {}
          checkpoint["error"] = error_message

          @store.db[:operation_progress]
            .where(id: op[:id])
            .update(
              status: "failed",
              completed_at: now,
              checkpoint_data: JSON.generate(checkpoint)
            )
        end

        count
      end

      private

      # Mark stale operations as failed before starting new operation
      def cleanup_stale_operations!(operation_type, scope)
        threshold_time = (Time.now.utc - STALE_THRESHOLD_SECONDS).iso8601
        now = Time.now.utc.iso8601
        error_message = "Automatically marked as failed - operation exceeded 24h timeout"

        stale = @store.db[:operation_progress]
          .where(operation_type: operation_type, scope: scope, status: "running")
          .where { started_at < threshold_time }

        # Fetch each stale operation, update checkpoint in Ruby, then save
        stale.all.each do |op|
          checkpoint = op[:checkpoint_data] ? JSON.parse(op[:checkpoint_data]) : {}
          checkpoint["error"] = error_message

          @store.db[:operation_progress]
            .where(id: op[:id])
            .update(
              status: "failed",
              completed_at: now,
              checkpoint_data: JSON.generate(checkpoint)
            )
        end
      end
    end
  end
end
