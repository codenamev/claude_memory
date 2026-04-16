# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing a fact in the memory system.
    # Encapsulates business logic and validation. Instances are immutable (frozen).
    class Fact
      attr_reader :id, :docid, :subject_name, :predicate, :object_literal,
        :status, :confidence, :scope, :project_path,
        :valid_from, :valid_to, :created_at

      # @param attributes [Hash] fact attributes
      # @option attributes [Integer] :id database primary key
      # @option attributes [Integer] :docid FTS document id
      # @option attributes [String] :subject_name entity name of the subject
      # @option attributes [String] :predicate relationship type (required)
      # @option attributes [String] :object_literal literal value (required)
      # @option attributes [String] :status one of "active", "superseded", "rejected", "disputed"
      # @option attributes [Float] :confidence score between 0 and 1 (default: 1.0)
      # @option attributes [String] :scope "project" or "global" (default: "project")
      # @option attributes [String] :project_path path for project-scoped facts
      # @option attributes [String] :valid_from ISO 8601 start of validity
      # @option attributes [String] :valid_to ISO 8601 end of validity (nil if current)
      # @option attributes [String] :created_at ISO 8601 creation timestamp
      # @raise [ArgumentError] if predicate, object_literal, or confidence is invalid
      def initialize(attributes)
        @id = attributes[:id]
        @docid = attributes[:docid]
        @subject_name = attributes[:subject_name]
        @predicate = attributes[:predicate]
        @object_literal = attributes[:object_literal]
        @status = attributes[:status] || "active"
        @confidence = attributes[:confidence] || 1.0
        @scope = attributes[:scope] || "project"
        @project_path = attributes[:project_path]
        @valid_from = attributes[:valid_from]
        @valid_to = attributes[:valid_to]
        @created_at = attributes[:created_at]

        validate!
        freeze
      end

      # @return [Boolean] true when status is "active"
      def active?
        status == "active"
      end

      # @return [Boolean] true when status is "superseded"
      def superseded?
        status == "superseded"
      end

      # @return [Boolean] true when status is "rejected"
      def rejected?
        status == "rejected"
      end

      # @return [Boolean] true when scope is "global"
      def global?
        scope == "global"
      end

      # @return [Boolean] true when scope is "project"
      def project?
        scope == "project"
      end

      # @return [Hash] all attributes as a plain hash
      def to_h
        {
          id: id,
          docid: docid,
          subject_name: subject_name,
          predicate: predicate,
          object_literal: object_literal,
          status: status,
          confidence: confidence,
          scope: scope,
          project_path: project_path,
          valid_from: valid_from,
          valid_to: valid_to,
          created_at: created_at
        }
      end

      private

      def validate!
        raise ArgumentError, "predicate required" if predicate.nil? || predicate.empty?
        raise ArgumentError, "object_literal required" if object_literal.nil? || object_literal.empty?
        raise ArgumentError, "confidence must be between 0 and 1" unless (0..1).cover?(confidence)
      end
    end
  end
end
