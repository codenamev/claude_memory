# frozen_string_literal: true

module ClaudeMemory
  module Ingest
    class PrivacyTag
      attr_reader :name

      def initialize(name)
        @name = name.to_s.strip
        validate!
        freeze
      end

      def pattern
        /<#{Regexp.escape(@name)}>.*?<\/#{Regexp.escape(@name)}>/m
      end

      def strip_from(text)
        # Strip repeatedly to handle nested tags
        result = text
        loop do
          new_result = result.gsub(pattern, "")
          break if new_result == result
          result = new_result
        end
        result
      end

      def ==(other)
        other.is_a?(PrivacyTag) && other.name == name
      end

      def eql?(other)
        self == other
      end

      def hash
        name.hash
      end

      private

      def validate!
        raise Error, "Tag name cannot be empty" if @name.empty?
      end
    end
  end
end
