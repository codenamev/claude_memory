# frozen_string_literal: true

module ClaudeMemory
  module Store
    # Retry logic for SQLite database operations.
    # Handles busy/locked errors from concurrent access by multiple hook processes.
    module RetryHandler
      MAX_RETRIES = 5
      RETRY_BASE_DELAY = 0.1 # seconds, with exponential backoff

      def with_retry(operation_name = "database operation")
        retries = 0
        begin
          yield
        rescue Sequel::DatabaseError, Extralite::Error, Extralite::BusyError => e
          if retryable_error?(e) && retries < MAX_RETRIES
            retries += 1
            delay = RETRY_BASE_DELAY * (2**retries)
            sleep(delay)
            retry
          end
          raise
        end
      end

      def transaction_with_retry(&block)
        with_retry("transaction") do
          @db.transaction(&block)
        end
      end

      private

      def retryable_error?(error)
        message = error.message.downcase
        message.include?("busy") || message.include?("locked")
      end

      def connect_database(db_path)
        retries = 0
        begin
          Sequel.connect(
            "extralite:#{db_path}",
            connect_sqls: [
              "PRAGMA busy_timeout = 1000",
              "PRAGMA journal_mode = WAL",
              "PRAGMA synchronous = NORMAL"
            ]
          )
        rescue Sequel::DatabaseConnectionError, Extralite::Error => e
          retries += 1
          if retries <= MAX_RETRIES && retryable_error?(e)
            sleep(RETRY_BASE_DELAY * (2**retries))
            retry
          end
          raise
        end
      end
    end
  end
end
