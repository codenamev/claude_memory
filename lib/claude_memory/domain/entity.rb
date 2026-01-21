# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing an entity (database, framework, person, etc.)
    class Entity
      attr_reader :id, :type, :canonical_name, :slug, :created_at

      def initialize(attributes)
        @id = attributes[:id]
        @type = attributes[:type]
        @canonical_name = attributes[:canonical_name]
        @slug = attributes[:slug]
        @created_at = attributes[:created_at]

        validate!
        freeze
      end

      def database?
        type == "database"
      end

      def framework?
        type == "framework"
      end

      def person?
        type == "person"
      end

      def to_h
        {
          id: id,
          type: type,
          canonical_name: canonical_name,
          slug: slug,
          created_at: created_at
        }
      end

      private

      def validate!
        raise ArgumentError, "type required" if type.nil? || type.empty?
        raise ArgumentError, "canonical_name required" if canonical_name.nil? || canonical_name.empty?
        raise ArgumentError, "slug required" if slug.nil? || slug.empty?
      end
    end
  end
end
