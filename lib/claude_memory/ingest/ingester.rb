# frozen_string_literal: true

require "digest"

module ClaudeMemory
  module Ingest
    class Ingester
      def initialize(store, fts: nil)
        @store = store
        @fts = fts || Index::LexicalFTS.new(store)
      end

      def ingest(source:, session_id:, transcript_path:)
        current_offset = @store.get_delta_cursor(session_id, transcript_path) || 0
        delta, new_offset = TranscriptReader.read_delta(transcript_path, current_offset)

        return {status: :no_change, bytes_read: 0} if delta.nil?

        text_hash = Digest::SHA256.hexdigest(delta)
        content_id = @store.upsert_content_item(
          source: source,
          session_id: session_id,
          transcript_path: transcript_path,
          text_hash: text_hash,
          byte_len: delta.bytesize,
          raw_text: delta
        )

        @fts.index_content_item(content_id, delta)
        @store.update_delta_cursor(session_id, transcript_path, new_offset)

        {status: :ingested, content_id: content_id, bytes_read: delta.bytesize}
      end
    end
  end
end
