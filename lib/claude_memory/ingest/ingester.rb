# frozen_string_literal: true

require "digest"

module ClaudeMemory
  module Ingest
    class Ingester
      def initialize(store, fts: nil, env: ENV, metadata_extractor: nil, tool_extractor: nil)
        @store = store
        @fts = fts || Index::LexicalFTS.new(store)
        @config = Configuration.new(env)
        @metadata_extractor = metadata_extractor || MetadataExtractor.new
        @tool_extractor = tool_extractor || ToolExtractor.new
      end

      def ingest(source:, session_id:, transcript_path:, project_path: nil)
        # Check if file has been modified since last ingestion (incremental sync)
        unless should_ingest?(transcript_path)
          return {status: :skipped, bytes_read: 0, reason: "unchanged"}
        end

        current_offset = @store.get_delta_cursor(session_id, transcript_path) || 0
        delta, new_offset = TranscriptReader.read_delta(transcript_path, current_offset)

        return {status: :no_change, bytes_read: 0} if delta.nil?

        # Extract session metadata and tool calls before sanitization
        metadata = @metadata_extractor.extract(delta)
        tool_calls = @tool_extractor.extract(delta)

        # Strip privacy tags before storing
        delta = ContentSanitizer.strip_tags(delta)

        resolved_project = project_path || detect_project_path

        # Get source file mtime for incremental sync
        source_mtime = File.exist?(transcript_path) ? File.mtime(transcript_path).utc.iso8601 : nil

        text_hash = Digest::SHA256.hexdigest(delta)

        # Wrap entire ingestion pipeline in transaction for atomicity
        # If any step fails, cursor position is not updated, allowing retry
        content_id = nil
        begin
          content_id = with_retry do
            @store.db.transaction do
              content_id = @store.upsert_content_item(
                source: source,
                session_id: session_id,
                transcript_path: transcript_path,
                project_path: resolved_project,
                text_hash: text_hash,
                byte_len: delta.bytesize,
                raw_text: delta,
                git_branch: metadata[:git_branch],
                cwd: metadata[:cwd],
                claude_version: metadata[:claude_version],
                thinking_level: metadata[:thinking_level],
                source_mtime: source_mtime
              )

              # Store tool calls if any were extracted
              @store.insert_tool_calls(content_id, tool_calls) unless tool_calls.empty?

              # FTS indexing (FTS5 supports transactions)
              @fts.index_content_item(content_id, delta)

              # Update cursor LAST - only after all other operations succeed
              # This ensures that if any step fails, we can retry from the same offset
              @store.update_delta_cursor(session_id, transcript_path, new_offset)

              content_id
            end
          end
        rescue SQLite3::BusyException => e
          # Re-raise BusyException with context after all retries exhausted
          raise StandardError, "Ingestion failed for session #{session_id} after retries: #{e.message}"
        rescue => e
          # Re-raise other errors with context for better error messages
          raise StandardError, "Ingestion failed for session #{session_id}: #{e.message}"
        end

        {status: :ingested, content_id: content_id, bytes_read: delta.bytesize, project_path: resolved_project}
      end

      private

      # Retry database operations with exponential backoff + jitter
      # This handles concurrent access when MCP server and hooks both write simultaneously
      # With busy_timeout=30000ms, each attempt waits up to 30s before raising BusyException
      # Total potential wait time: 30s * 10 attempts + backoff delays = ~5 minutes max
      def with_retry(max_attempts: 10, base_delay: 0.2, max_delay: 5.0)
        attempt = 0
        begin
          attempt += 1
          yield
        rescue SQLite3::BusyException
          if attempt < max_attempts
            # Exponential backoff with jitter to avoid thundering herd
            exponential_delay = [base_delay * (2**(attempt - 1)), max_delay].min
            jitter = rand * exponential_delay * 0.5
            total_delay = exponential_delay + jitter
            sleep(total_delay)
            retry
          else
            raise
          end
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

      def detect_project_path
        @config.project_dir
      end
    end
  end
end
