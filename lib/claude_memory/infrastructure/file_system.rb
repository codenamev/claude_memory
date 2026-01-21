# frozen_string_literal: true

require "fileutils"
require "digest/sha2"

module ClaudeMemory
  module Infrastructure
    # Real filesystem implementation
    # Wraps File and FileUtils for dependency injection
    class FileSystem
      def exist?(path)
        File.exist?(path)
      end

      def read(path)
        File.read(path)
      end

      def write(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def file_hash(path)
        Digest::SHA256.file(path).hexdigest
      end
    end
  end
end
