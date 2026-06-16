# frozen_string_literal: true

module ClaudeMemory
  module Domain
    # Domain model representing an episodic observation — "what happened",
    # as opposed to a Fact's "what is true". Instances are immutable (frozen).
    #
    # Priority follows Mastra's traffic-light scheme and is an internal signal
    # for the Observer/Reflector pipeline: 1 = important (🔴), 2 = maybe (🟡),
    # 3 = info only (🟢). Only 🔴 is meant to survive into the actor's prompt.
    class Observation
      KINDS = %w[user_statement agent_action tool_result preference decision event].freeze
      IMPORTANT = 1
      MAYBE = 2
      INFO = 3

      attr_reader :id, :body, :kind, :priority, :scope, :project_path,
        :source_content_item_id, :consolidated_into, :token_count,
        :status, :session_id, :observed_at, :created_at, :reflected_at

      # @param attributes [Hash] observation attributes (see column list)
      # @raise [ArgumentError] if body is blank or priority is out of range
      def initialize(attributes)
        @id = attributes[:id]
        @body = attributes[:body]
        @kind = attributes[:kind] || "event"
        @priority = attributes[:priority] || INFO
        @scope = attributes[:scope] || "project"
        @project_path = attributes[:project_path]
        @source_content_item_id = attributes[:source_content_item_id]
        @consolidated_into = attributes[:consolidated_into]
        @token_count = attributes[:token_count]
        @status = attributes[:status] || "active"
        @session_id = attributes[:session_id]
        @observed_at = attributes[:observed_at]
        @created_at = attributes[:created_at]
        @reflected_at = attributes[:reflected_at]

        validate!
        freeze
      end

      # @return [Boolean] true when the observation has not been consolidated away
      def active?
        status == "active"
      end

      # @return [Boolean] true when the Reflector has merged this into another
      def consolidated?
        status == "consolidated"
      end

      # @return [Boolean] true for 🔴 — the only priority shown to the actor
      def important?
        priority == IMPORTANT
      end

      # @return [Boolean] true when scope is "global"
      def global?
        scope == "global"
      end

      # @return [Hash] all attributes as a plain hash
      def to_h
        {
          id: id,
          body: body,
          kind: kind,
          priority: priority,
          scope: scope,
          project_path: project_path,
          source_content_item_id: source_content_item_id,
          consolidated_into: consolidated_into,
          token_count: token_count,
          status: status,
          session_id: session_id,
          observed_at: observed_at,
          created_at: created_at,
          reflected_at: reflected_at
        }
      end

      private

      def validate!
        raise ArgumentError, "body required" if body.nil? || body.empty?
        raise ArgumentError, "priority must be 1, 2, or 3" unless (IMPORTANT..INFO).cover?(priority)
      end
    end
  end
end
