# frozen_string_literal: true

module ClaudeMemory
  module Ingest
    class ContentSanitizer
      SYSTEM_TAGS = ["claude-memory-context"].freeze
      USER_TAGS = ["private", "no-memory", "secret"].freeze
      MAX_TAG_COUNT = 100

      def self.strip_tags(text)
        tags = Pure.all_tags
        validate_tag_count!(text, tags)
        Pure.strip_tags(text, tags)
      end

      def self.validate_tag_count!(text, tags)
        count = Pure.count_tags(text, tags)
        raise Error, "Too many privacy tags (#{count}), possible ReDoS attack" if count > MAX_TAG_COUNT
      end

      module Pure
        def self.all_tags
          @all_tags ||= begin
            all_tag_names = ContentSanitizer::SYSTEM_TAGS + ContentSanitizer::USER_TAGS
            all_tag_names.map { |name| PrivacyTag.new(name) }
          end
        end

        def self.strip_tags(text, tags)
          tags.reduce(text) { |result, tag| tag.strip_from(result) }
        end

        def self.count_tags(text, tags)
          tags.sum do |tag|
            opening_pattern = /<#{Regexp.escape(tag.name)}>/
            text.scan(opening_pattern).size
          end
        end
      end
    end
  end
end
