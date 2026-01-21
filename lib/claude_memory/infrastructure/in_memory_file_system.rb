# frozen_string_literal: true

require "digest/sha2"

module ClaudeMemory
  module Infrastructure
    # In-memory filesystem implementation for fast testing
    # Does not touch the real filesystem
    class InMemoryFileSystem
      def initialize
        @files = {}
      end

      def exist?(path)
        @files.key?(path)
      end

      def read(path)
        @files.fetch(path) { raise Errno::ENOENT, path }
      end

      def write(path, content)
        @files[path] = content
      end

      def file_hash(path)
        content = read(path)
        Digest::SHA256.hexdigest(content)
      end
    end
  end
end
