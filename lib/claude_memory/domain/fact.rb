# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing a fact in the memory system
    # Encapsulates business logic and validation
    class Fact
      attr_reader :id, :subject_name, :predicate, :object_literal,
        :status, :confidence, :scope, :project_path,
        :valid_from, :valid_to, :created_at

      def initialize(attributes)
        @id = attributes[:id]
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

      def active?
        status == "active"
      end

      def superseded?
        status == "superseded"
      end

      def global?
        scope == "global"
      end

      def project?
        scope == "project"
      end

      def to_h
        {
          id: id,
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
