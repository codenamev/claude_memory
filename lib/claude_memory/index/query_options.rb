# frozen_string_literal: true

module ClaudeMemory
  module Index
    class QueryOptions
      SCOPE_ALL = :all
      SCOPE_PROJECT = :project
      SCOPE_GLOBAL = :global

      DEFAULT_LIMIT = 20
      DEFAULT_SCOPE = SCOPE_ALL

      attr_reader :query_text, :limit, :scope, :source

      def initialize(query_text:, limit: DEFAULT_LIMIT, scope: DEFAULT_SCOPE, source: nil)
        @query_text = query_text
        @limit = limit
        @scope = scope.to_sym
        @source = source&.to_sym
        freeze
      end

      def for_project
        self.class.new(
          query_text: query_text,
          limit: limit,
          scope: scope,
          source: :project
        )
      end

      def for_global
        self.class.new(
          query_text: query_text,
          limit: limit,
          scope: scope,
          source: :global
        )
      end

      def with_limit(new_limit)
        self.class.new(
          query_text: query_text,
          limit: new_limit,
          scope: scope,
          source: source
        )
      end

      def ==(other)
        other.is_a?(QueryOptions) &&
          other.query_text == query_text &&
          other.limit == limit &&
          other.scope == scope &&
          other.source == source
      end

      def eql?(other)
        self == other
      end

      def hash
        [query_text, limit, scope, source].hash
      end
    end
  end
end
