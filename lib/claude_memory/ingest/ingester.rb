# frozen_string_literal: true

require "digest"

module ClaudeMemory
  module Ingest
    # Delta-based transcript ingestion with cursor tracking.
    # Reads new content from transcripts, extracts metadata and tool calls,
    # sanitizes private tags, and persists to the content_items table with FTS indexing.
    class Ingester
      # @param store [Store::SQLiteStore] database store for persistence
      # @param fts [Index::LexicalFTS, nil] full-text search index (default: new from store)
      # @param env [Hash] environment variables
      # @param metadata_extractor [MetadataExtractor, nil] extracts git branch, cwd, etc.
      # @param tool_extractor [ToolExtractor, nil] extracts tool calls from transcript text
      # @param tool_filter [ToolFilter, nil] filters irrelevant tool calls
      # @param observation_compressor [ObservationCompressor, nil] compresses tool observations
      def initialize(store, fts: nil, env: ENV, metadata_extractor: nil, tool_extractor: nil, tool_filter: nil, observation_compressor: nil)
        @store = store
        @fts = fts || Index::LexicalFTS.new(store)
        @config = Configuration.new(env)
        @metadata_extractor = metadata_extractor || MetadataExtractor.new
        @tool_extractor = tool_extractor || ToolExtractor.new
        @tool_filter = tool_filter || ToolFilter.new
        @observation_compressor = observation_compressor || ObservationCompressor.new
      end

      # Ingest new content from a transcript file
      # @param source [String] content source identifier (e.g., "hook", "cli")
      # @param session_id [String] Claude session ID
      # @param transcript_path [String] path to the transcript file
      # @param project_path [String, nil] project root (defaults to detected path)
      # @return [Hash] result with :status (:ingested, :skipped, or :no_change),
      #   :content_id, :bytes_read, and optional :reason
      def ingest(source:, session_id:, transcript_path:, project_path: nil)
        unless should_ingest?(transcript_path)
          ClaudeMemory.logger.debug("ingest", message: "Skipped unchanged file", transcript_path: transcript_path)
          return {status: :skipped, bytes_read: 0, reason: "unchanged"}
        end

        prepared = prepare_delta(session_id, transcript_path, project_path)
        return {status: :no_change, bytes_read: 0} if prepared.nil?
        return {status: :skipped, bytes_read: 0, reason: "session_excluded"} if prepared == :excluded

        content_id = persist_content(source, session_id, transcript_path, prepared)

        log_ingestion(content_id, prepared, session_id)
        {status: :ingested, content_id: content_id, bytes_read: prepared[:delta].bytesize, project_path: prepared[:project_path]}
      end

      private

      # Tags that cause the entire delta to be skipped when present.
      # Different from ContentSanitizer which strips tag content but keeps the rest.
      EXCLUSION_TAGS = ["no-memory", "private", ClaudeMemory::SELF_CONTEXT_MARKER].freeze

      def prepare_delta(session_id, transcript_path, project_path)
        current_offset = @store.get_delta_cursor(session_id, transcript_path) || 0
        delta, new_offset = TranscriptReader.read_delta(transcript_path, current_offset)
        return nil if delta.nil?

        # Skip entire delta if session exclusion markers are present
        if session_excluded?(delta)
          # Advance cursor so we don't re-check this content
          @store.update_delta_cursor(session_id, transcript_path, new_offset)
          return :excluded
        end

        metadata = @metadata_extractor.extract(delta)
        tool_calls = @tool_filter.filter(@tool_extractor.extract(delta))
        tool_calls = compress_tool_calls(tool_calls)
        delta = ContentSanitizer.strip_tags(delta)

        {
          delta: delta,
          new_offset: new_offset,
          metadata: metadata,
          tool_calls: tool_calls,
          project_path: project_path || detect_project_path,
          source_mtime: File.exist?(transcript_path) ? File.mtime(transcript_path).utc.iso8601 : nil,
          text_hash: Digest::SHA256.hexdigest(delta)
        }
      end

      def persist_content(source, session_id, transcript_path, prepared)
        with_retry do
          @store.db.transaction do
            content_id = @store.upsert_content_item(
              source: source,
              session_id: session_id,
              transcript_path: transcript_path,
              project_path: prepared[:project_path],
              text_hash: prepared[:text_hash],
              byte_len: prepared[:delta].bytesize,
              raw_text: prepared[:delta],
              git_branch: prepared[:metadata][:git_branch],
              cwd: prepared[:metadata][:cwd],
              claude_version: prepared[:metadata][:claude_version],
              thinking_level: prepared[:metadata][:thinking_level],
              source_mtime: prepared[:source_mtime]
            )

            @store.insert_tool_calls(content_id, prepared[:tool_calls]) unless prepared[:tool_calls].empty?
            @fts.index_content_item(content_id, prepared[:delta])
            @store.update_delta_cursor(session_id, transcript_path, prepared[:new_offset])

            content_id
          end
        end
      rescue Extralite::BusyError => e
        raise StandardError, "Ingestion failed for session #{session_id} after retries: #{e.message}"
      rescue => e
        raise StandardError, "Ingestion failed for session #{session_id}: #{e.message}"
      end

      def log_ingestion(content_id, prepared, session_id)
        ClaudeMemory.logger.info("ingest",
          message: "Ingested content",
          content_id: content_id,
          bytes_read: prepared[:delta].bytesize,
          session_id: session_id,
          tool_calls: prepared[:tool_calls].size)
      end

      # Retry database operations with exponential backoff + jitter
      # This handles concurrent access when MCP server and hooks both write simultaneously
      # With busy_timeout=30000ms, each attempt waits up to 30s before raising BusyError
      # Handles both "busy" and "locked" error messages from SQLite/Extralite
      # Total potential wait time: 30s * 10 attempts + backoff delays = ~5 minutes max
      def with_retry(max_attempts: 10, base_delay: 0.2, max_delay: 5.0)
        attempt = 0
        begin
          attempt += 1
          yield
        rescue Extralite::BusyError, Sequel::DatabaseError => e
          # Handle busy/locked errors from extralite adapter
          is_busy = e.is_a?(Extralite::BusyError) ||
            e.message.include?("busy") ||
            e.message.include?("locked")
          if is_busy && attempt < max_attempts
            # Exponential backoff with jitter to avoid thundering herd
            exponential_delay = [base_delay * (2**(attempt - 1)), max_delay].min
            jitter = rand * exponential_delay * 0.5
            total_delay = exponential_delay + jitter
            ClaudeMemory.logger.warn("ingest",
              message: "Database busy, retrying",
              attempt: attempt,
              max_attempts: max_attempts,
              delay_seconds: total_delay.round(3))
            sleep(total_delay)
            retry
          elsif is_busy
            # Max attempts reached, give up
            raise
          else
            # Not a busy/locked error, re-raise immediately
            raise
          end
        end
      end

      def compress_tool_calls(tool_calls)
        tool_calls.map do |tc|
          summary = @observation_compressor.compress(tc[:tool_name], tc[:tool_input])
          tc.merge(compressed_summary: summary)
        end
      end

      def should_ingest?(transcript_path)
        return true unless File.exist?(transcript_path)

        file_mtime = File.mtime(transcript_path).utc.iso8601

        # Check if we've already processed this version of the file
        existing = @store.content_item_by_transcript_and_mtime(transcript_path, file_mtime)

        # Ingest if we haven't seen this version before
        existing.nil?
      end

      def session_excluded?(text)
        EXCLUSION_TAGS.any? { |tag| text.include?("<#{tag}>") }
      end

      def detect_project_path
        @config.project_dir
      end
    end
  end
end
