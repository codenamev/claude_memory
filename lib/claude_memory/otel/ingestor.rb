# frozen_string_literal: true

require_relative "../core/result"

module ClaudeMemory
  module OTel
    # Imperative shell for OTel ingestion. Takes the parsed-row hashes
    # produced by OtlpJsonEnvelope and writes them in a single batched
    # transaction. Returns Core::Result so the HTTP server can map outcome
    # to status code without rescue clauses.
    #
    # The ingestor accepts a `:metrics`, `:events`, or `:traces` payload —
    # one kind per call, matching how OTLP/HTTP separates the three
    # endpoints. Wrap each batch in transaction_with_retry so a partial
    # failure mid-insert leaves zero rows behind.
    class Ingestor
      def initialize(store)
        @store = store
      end

      # @param payload [Hash] one of {metrics: [...]}, {events: [...]},
      #   {traces: [...]}. Other keys are ignored.
      # @return [Core::Result] success carries inserted-count Hash;
      #   failure carries an error message
      def ingest(payload)
        return Core::Result.failure("payload must be a Hash") unless payload.is_a?(Hash)

        counts = {metrics: 0, events: 0, traces: 0}
        @store.transaction_with_retry do
          counts[:metrics] = insert_metrics(payload[:metrics] || payload["metrics"])
          counts[:events] = insert_events(payload[:events] || payload["events"])
          counts[:traces] = insert_traces(payload[:traces] || payload["traces"])
        end
        Core::Result.success(counts)
      rescue Sequel::DatabaseError, Extralite::Error, ArgumentError, KeyError => e
        Core::Result.failure(e.message)
      end

      private

      def insert_metrics(rows)
        rows.is_a?(Array) ? @store.bulk_insert_otel_metrics(rows) : 0
      end

      def insert_events(rows)
        rows.is_a?(Array) ? @store.bulk_insert_otel_events(rows) : 0
      end

      def insert_traces(rows)
        rows.is_a?(Array) ? @store.bulk_insert_otel_traces(rows) : 0
      end
    end
  end
end
