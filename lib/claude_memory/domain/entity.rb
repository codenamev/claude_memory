# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing an entity (database, framework, person, etc.).
    # Instances are immutable (frozen).
    class Entity
      attr_reader :id, :type, :canonical_name, :slug, :created_at

      # @param attributes [Hash] entity attributes
      # @option attributes [Integer] :id database primary key
      # @option attributes [String] :type entity category (required, e.g. "database", "framework", "person")
      # @option attributes [String] :canonical_name display name (required)
      # @option attributes [String] :slug URL-safe identifier (required)
      # @option attributes [String] :created_at ISO 8601 creation timestamp
      # @raise [ArgumentError] if type, canonical_name, or slug is blank
      def initialize(attributes)
        @id = attributes[:id]
        @type = attributes[:type]
        @canonical_name = attributes[:canonical_name]
        @slug = attributes[:slug]
        @created_at = attributes[:created_at]

        validate!
        freeze
      end

      # @return [Boolean] true when type is "database"
      def database?
        type == "database"
      end

      # @return [Boolean] true when type is "framework"
      def framework?
        type == "framework"
      end

      # @return [Boolean] true when type is "person"
      def person?
        type == "person"
      end

      # @return [Hash] all attributes as a plain hash
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
