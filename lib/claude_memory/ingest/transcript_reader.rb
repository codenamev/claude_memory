# frozen_string_literal: true

module ClaudeMemory
  module Ingest
    class TranscriptReader
      class FileNotFoundError < ClaudeMemory::Error; end

      def self.read_delta(path, from_offset)
        raise FileNotFoundError, "File not found: #{path}" unless File.exist?(path)

        file_size = File.size(path)
        effective_offset = (from_offset > file_size) ? 0 : from_offset

        return [nil, effective_offset] if file_size == effective_offset

        content = File.read(path, nil, effective_offset)
        [content, file_size]
      end
    end
  end
end
