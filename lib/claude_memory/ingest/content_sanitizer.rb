# frozen_string_literal: true

module ClaudeMemory
  module Ingest
    # Strips privacy tags from transcript content before ingestion.
    #
    # Note: No tag count limit is enforced. The regex pattern /<tag>.*?<\/tag>/m
    # is provably safe from ReDoS (non-greedy matching with clear delimiters).
    # Performance is O(n) and excellent even with 1000+ tags (~0.6ms).
    # Long Claude sessions legitimately accumulate many tags (100-200+).
    class ContentSanitizer
      SYSTEM_TAGS = ["claude-memory-context"].freeze
      USER_TAGS = ["private", "no-memory", "secret"].freeze

      def self.strip_tags(text)
        tags = Pure.all_tags
        Pure.strip_tags(text, tags)
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
