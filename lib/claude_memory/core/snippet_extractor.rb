# frozen_string_literal: true

module ClaudeMemory
  module Core
    # Extracts relevant snippets from raw content based on query terms.
    # Finds the line with the most query term matches and returns
    # surrounding context (1 line before + 2 lines after).
    # Follows Functional Core pattern - pure transformations, no I/O.
    class SnippetExtractor
      CONTEXT_BEFORE = 1
      CONTEXT_AFTER = 2
      MAX_SNIPPET_LENGTH = 500

      # Extract the best snippet from content matching the query
      # @param content [String] Raw text content
      # @param query [String] Search query
      # @return [String, nil] Best matching snippet or nil if no content
      def self.extract(content, query)
        parsed = parse_and_find(content, query)
        return nil unless parsed

        build_snippet(parsed[:lines], parsed[:best_line_idx])
      end

      # Extract snippet and return line range information
      # @param content [String] Raw text content
      # @param query [String] Search query
      # @return [Hash, nil] Hash with :snippet, :line_start, :line_end or nil
      def self.extract_with_lines(content, query)
        parsed = parse_and_find(content, query)
        return nil unless parsed

        lines = parsed[:lines]
        best_line_idx = parsed[:best_line_idx]
        start_idx = [best_line_idx - CONTEXT_BEFORE, 0].max
        end_idx = [best_line_idx + CONTEXT_AFTER, lines.size - 1].min

        {
          snippet: build_snippet(lines, best_line_idx),
          line_start: start_idx + 1, # 1-indexed
          line_end: end_idx + 1       # 1-indexed
        }
      end

      # @api private
      def self.parse_and_find(content, query)
        return nil if content.nil? || content.empty? || query.nil? || query.empty?

        lines = content.lines.map(&:chomp)
        return nil if lines.empty?

        terms = tokenize_query(query)
        return nil if terms.empty?

        best_line_idx = find_best_line(lines, terms)
        return nil unless best_line_idx

        {lines: lines, best_line_idx: best_line_idx}
      end

      # @api private
      def self.tokenize_query(query)
        query.downcase.split(/\s+/).reject { |t| t.length < 2 }
      end

      # @api private
      def self.find_best_line(lines, terms)
        best_idx = nil
        best_score = 0

        lines.each_with_index do |line, idx|
          downcased = line.downcase
          score = terms.count { |term| downcased.include?(term) }
          if score > best_score
            best_score = score
            best_idx = idx
          end
        end

        best_idx
      end

      # @api private
      def self.build_snippet(lines, center_idx)
        start_idx = [center_idx - CONTEXT_BEFORE, 0].max
        end_idx = [center_idx + CONTEXT_AFTER, lines.size - 1].min

        snippet = lines[start_idx..end_idx].join("\n")
        truncate(snippet)
      end

      # @api private
      def self.truncate(text)
        return text if text.length <= MAX_SNIPPET_LENGTH
        text[0, MAX_SNIPPET_LENGTH - 3] + "..."
      end
    end
  end
end
